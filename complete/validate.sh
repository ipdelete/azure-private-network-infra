#!/bin/bash

# ─────────────────────────────────────────────
# 🔍 Infrastructure Validation Script
# ─────────────────────────────────────────────
# This script validates the deployed Azure infrastructure
# and provides status information for all components

set -e

# 🔧 Configuration
RESOURCE_GROUP="aet-pi-localdev-es2-tst4"
VM_NAME="vm-pi-localdev"
VNET_NAME="vnet-pi-localdev"
BASTION_NAME="bastion-pi-localdev"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Azure Private Network Infrastructure Validation${NC}"
echo "════════════════════════════════════════════════════════════"
echo "📅 Validation run: $(date)"
echo "🏗️  Resource Group: $RESOURCE_GROUP"
echo ""

# Function to check resource status
check_resource() {
    local resource_type=$1
    local resource_name=$2
    local check_command=$3
    
    echo -n "• $resource_type: "
    if eval "$check_command" &>/dev/null; then
        echo -e "${GREEN}✅ $resource_name${NC}"
        return 0
    else
        echo -e "${RED}❌ $resource_name (not found)${NC}"
        return 1
    fi
}

# Function to get resource info
get_resource_info() {
    local resource_type=$1
    local query=$2
    local resource_name=$3
    
    if eval "$query" &>/dev/null; then
        eval "$query"
    else
        echo -e "  ${RED}❌ Could not retrieve $resource_type information${NC}"
    fi
}

echo -e "${YELLOW}🏗️  Resource Group Status:${NC}"
check_resource "Resource Group" "$RESOURCE_GROUP" "az group show --name $RESOURCE_GROUP"

echo ""
echo -e "${YELLOW}🌐 Network Infrastructure:${NC}"
check_resource "Virtual Network" "$VNET_NAME" "az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME"

if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
    echo "  📊 Subnet Information:"
    az network vnet subnet list \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --query "[].{Name:name, AddressPrefix:addressPrefix, NSG:networkSecurityGroup.id}" \
        --output table | sed 's/^/  /'
fi

check_resource "NAT Gateway" "NAT Gateway" "az network nat gateway list --resource-group $RESOURCE_GROUP --query '[0].name'"

echo ""
echo -e "${YELLOW}💾 Storage Infrastructure:${NC}"
STORAGE_ACCOUNT=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'sapifile')].name" -o tsv)
if [ -n "$STORAGE_ACCOUNT" ]; then
    echo -e "• Storage Account: ${GREEN}✅ $STORAGE_ACCOUNT${NC}"
    
    # Check NFS share
    echo "  📊 NFS Share Information:"
    az storage share list \
        --account-name "$STORAGE_ACCOUNT" \
        --query "[].{Name:name, Quota:quota, Protocol:enabledProtocols}" \
        --output table | sed 's/^/  /'
        
    # Check private endpoint
    PRIVATE_ENDPOINT=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, '$STORAGE_ACCOUNT')].name" -o tsv)
    if [ -n "$PRIVATE_ENDPOINT" ]; then
        echo -e "• Private Endpoint: ${GREEN}✅ $PRIVATE_ENDPOINT${NC}"
    else
        echo -e "• Private Endpoint: ${RED}❌ Not found${NC}"
    fi
else
    echo -e "• Storage Account: ${RED}❌ Not found${NC}"
fi

echo ""
echo -e "${YELLOW}💻 Virtual Machine:${NC}"
check_resource "Virtual Machine" "$VM_NAME" "az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME"

if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" &>/dev/null; then
    echo "  📊 VM Information:"
    az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --query "{Name:name, Size:hardwareProfile.vmSize, Status:provisioningState, OS:storageProfile.imageReference.offer}" \
        --output table | sed 's/^/  /'
    
    echo "  📊 Network Interface Information:"
    NIC_NAME="${VM_NAME}-nic"
    az network nic show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --query "{Name:name, PrivateIP:ipConfigurations[0].privateIPAddress, HasPublicIP:ipConfigurations[0].publicIPAddress!=null}" \
        --output table | sed 's/^/  /'
fi

echo ""
echo -e "${YELLOW}🏰 Azure Bastion:${NC}"
check_resource "Bastion Host" "$BASTION_NAME" "az network bastion show --resource-group $RESOURCE_GROUP --name $BASTION_NAME"

if az network bastion show --resource-group "$RESOURCE_GROUP" --name "$BASTION_NAME" &>/dev/null; then
    echo "  📊 Bastion Information:"
    az network bastion show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_NAME" \
        --query "{Name:name, State:provisioningState, Sku:sku.name}" \
        --output table | sed 's/^/  /'
    
    echo "  📊 Bastion Public IP:"
    BASTION_PIP="${BASTION_NAME}-pip"
    az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_PIP" \
        --query "{Name:name, IP:ipAddress, Method:publicIPAllocationMethod}" \
        --output table | sed 's/^/  /'
fi

echo ""
echo -e "${YELLOW}🔐 Security Configuration:${NC}"
echo "  📊 Network Security Groups:"
az network nsg list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[].{Name:name, Subnet:subnets[0].name, RuleCount:length(securityRules)}" \
    --output table | sed 's/^/  /'

echo ""
echo -e "${GREEN}📋 Connection Summary:${NC}"
if [ -n "$STORAGE_ACCOUNT" ]; then
    echo "🔗 Access VM via Azure Portal:"
    echo "  1. Navigate to Virtual Machines → $VM_NAME"
    echo "  2. Click 'Connect' → 'Bastion'"
    echo "  3. Username: azureuser"
    echo "  4. Authentication: SSH Private Key"
    echo ""
    echo "📁 NFS Share Location on VM:"
    echo "  /mount/$STORAGE_ACCOUNT/nfsshare"
    echo ""
    echo "🔍 VM Validation Commands:"
    echo "  sudo cloud-init status"
    echo "  df -h | grep nfs"
    echo "  ls -la /mount/$STORAGE_ACCOUNT/nfsshare"
    echo "  echo 'test' > /mount/$STORAGE_ACCOUNT/nfsshare/validation.txt"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Validation completed${NC}"
