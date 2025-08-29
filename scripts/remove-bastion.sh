#!/bin/bash

# ─────────────────────────────────────────────
# 🗑️  Bastion Removal Script
# ─────────────────────────────────────────────

# 🔧 Configuration
RESOURCE_GROUP="aet-pi-localdev-es2-tst4"
BASTION_NAME="bastion-pi-localdev"
PUBLIC_IP_NAME="bastion-pi-localdev-pip"

echo "🗑️  Bastion Removal Script"
echo "════════════════════════════════════════════"
echo "Resource Group: $RESOURCE_GROUP"
echo "Bastion Name: $BASTION_NAME"
echo "Public IP Name: $PUBLIC_IP_NAME"
echo ""
echo "⚠️  This will permanently delete:"
echo "   • Azure Bastion Host: $BASTION_NAME"
echo "   • Bastion Public IP: $PUBLIC_IP_NAME"
echo ""
echo "✅ This will PRESERVE:"
echo "   • Virtual Machine and all other infrastructure"
echo "   • Virtual Network & Subnets (including AzureBastionSubnet)"
echo "   • Storage Account & NFS Share"
echo "   • Network Security Groups"
echo ""

# Confirmation prompt
read -p "❓ Are you sure you want to remove the Bastion? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Operation cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting Bastion removal process..."

# Function to check if resource exists
check_resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "bastion")
            az network bastion show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
        "public-ip")
            az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &>/dev/null
            ;;
    esac
    return $?
}

# Step 1: Remove Azure Bastion Host
echo "🔄 Step 1: Removing Azure Bastion Host..."
if check_resource_exists "bastion" "$BASTION_NAME"; then
    echo "⏳ This will take 5-10 minutes to complete..."
    az network bastion delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BASTION_NAME" \
        --no-wait 
    
    if [ $? -eq 0 ]; then
        echo "✅ Bastion Host deletion completed successfully"
    else
        echo "❌ Failed to delete Bastion Host"
        exit 1
    fi
else
    echo "ℹ️  Bastion Host '$BASTION_NAME' not found (may already be deleted)"
fi

# Step 2: Remove Bastion Public IP
echo ""
echo "🔄 Step 2: Removing Bastion Public IP..."
if check_resource_exists "public-ip" "$PUBLIC_IP_NAME"; then
    az network public-ip delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --no-wait 
    
    if [ $? -eq 0 ]; then
        echo "✅ Bastion Public IP deletion completed successfully"
    else
        echo "❌ Failed to delete Bastion Public IP"
        exit 1
    fi
else
    echo "ℹ️  Bastion Public IP '$PUBLIC_IP_NAME' not found (may already be deleted)"
fi

echo ""
echo "🎉 Bastion removal process completed!"
echo ""
echo "📊 Summary:"
echo "   ✅ Azure Bastion Host '$BASTION_NAME' - Removed"
echo "   ✅ Bastion Public IP '$PUBLIC_IP_NAME' - Removed"
echo ""
echo "🔄 To redeploy Bastion with CLI SSH support:"
echo "   1. Update bas/main.bicep with 'enableTunneling: true'"
echo "   2. Fix bas/deploy.sh resource group name if needed"
echo "   3. Run: cd bas && ./deploy.sh"
echo ""
echo "⚠️  Note: The AzureBastionSubnet remains available for future deployments"
