#!/bin/bash

# ─────────────────────────────────────────────
# 🔐 SSH to VM via Azure Bastion Script
# ─────────────────────────────────────────────

# 🔧 Configuration
RESOURCE_GROUP="aet-pi-localdev-es2-tst4"
BASTION_NAME="bastion-pi-localdev"
VM_NAME="vm-pi-localdev"
USERNAME="azureuser"
SSH_KEY_PATH="$HOME/.ssh/vm-pi-localdev-key"

# 🎨 Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔐 SSH to VM via Azure Bastion${NC}"
echo "════════════════════════════════════════════"
echo "Resource Group: $RESOURCE_GROUP"
echo "Bastion Name: $BASTION_NAME"
echo "VM Name: $VM_NAME"
echo "Username: $USERNAME"
echo "SSH Key: $SSH_KEY_PATH"
echo ""

# Function to check if resource exists
check_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "bastion")
            az network bastion show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
        "vm")
            az vm show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
    esac
    return $?
}

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}❌ SSH private key not found at: $SSH_KEY_PATH${NC}"
    echo ""
    echo -e "${YELLOW}💡 To generate SSH keys, run:${NC}"
    echo "   cd vm && ./generate-ssh-key.sh"
    echo ""
    echo -e "${YELLOW}💡 Or specify a different key path:${NC}"
    echo "   export SSH_KEY_PATH=/path/to/your/private/key"
    echo "   ./scripts/ssh-to-vm.sh"
    exit 1
fi

# Check if Bastion exists
echo "🔍 Checking Bastion availability..."
if ! check_resource_exists "bastion" "$BASTION_NAME"; then
    echo -e "${RED}❌ Bastion Host '$BASTION_NAME' not found in resource group '$RESOURCE_GROUP'${NC}"
    echo ""
    echo -e "${YELLOW}💡 To deploy Bastion:${NC}"
    echo "   cd bas && ./deploy.sh"
    exit 1
fi

# Check if VM exists
echo "🔍 Checking VM availability..."
if ! check_resource_exists "vm" "$VM_NAME"; then
    echo -e "${RED}❌ Virtual Machine '$VM_NAME' not found in resource group '$RESOURCE_GROUP'${NC}"
    echo ""
    echo -e "${YELLOW}💡 To deploy VM:${NC}"
    echo "   cd vm && ./deploy.sh"
    exit 1
fi

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo -e "${RED}❌ Unable to get subscription ID. Please ensure you're logged in to Azure CLI.${NC}"
    exit 1
fi

# Build VM resource ID
VM_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME"

echo -e "${GREEN}✅ All resources found${NC}"
echo ""
echo "🚀 Connecting to VM via Bastion..."
echo "   Subscription: $SUBSCRIPTION_ID"
echo "   VM Resource ID: $VM_RESOURCE_ID"
echo ""
echo -e "${YELLOW}⏳ Establishing SSH connection (this may take a few seconds)...${NC}"

# SSH to VM via Bastion
az network bastion ssh \
  --name "$BASTION_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --target-resource-id "$VM_RESOURCE_ID" \
  --auth-type ssh-key \
  --username "$USERNAME" \
  --ssh-key "$SSH_KEY_PATH"

# Check result
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ SSH session completed successfully${NC}"
else
    echo ""
    echo -e "${RED}❌ SSH connection failed${NC}"
    echo ""
    echo -e "${YELLOW}💡 Troubleshooting tips:${NC}"
    echo "   1. Verify Bastion has 'enableTunneling: true' (requires Standard SKU)"
    echo "   2. Check VM is running: az vm get-instance-view --resource-group $RESOURCE_GROUP --name $VM_NAME"
    echo "   3. Verify SSH key permissions: chmod 600 $SSH_KEY_PATH"
    echo "   4. Check Azure CLI login: az account show"
    echo ""
    echo -e "${YELLOW}💡 Alternative connection via Azure Portal:${NC}"
    echo "   1. Go to Azure Portal → Virtual Machines → $VM_NAME"
    echo "   2. Click 'Connect' → 'Bastion'"
    echo "   3. Use SSH key authentication"
fi
