#!/bin/bash

# ─────────────────────────────────────────────
# 📦 Bicep Deployment Script: Azure Bastion
# ─────────────────────────────────────────────

# 🔧 Configurable variables
RESOURCE_GROUP_NAME="aet-pi-localdev-es2-tst3"  # Resource group name
BICEP_FILE="main.bicep"               # Bicep template file
PARAM_FILE="main.parameters.json"    # Parameter file
DEPLOYMENT_NAME="bastion-deploy-$(date +%s)"  # Unique deployment name

# 🚀 Run the deployment
echo "Starting Azure Bastion deployment: $DEPLOYMENT_NAME"
echo "Target Resource Group: $RESOURCE_GROUP_NAME"
echo ""
echo "⚠️  Note: Bastion deployment typically takes 10-15 minutes to complete."
echo ""

az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --name "$DEPLOYMENT_NAME"

# ✅ Check result
if [ $? -eq 0 ]; then
  echo "✅ Azure Bastion deployment succeeded."
  
  # 📊 Display Bastion info
  echo ""
  echo "📊 Bastion Information:"
  az network bastion show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "bastion-pi-localdev" \
    --query "{Name:name, ProvisioningState:provisioningState, Sku:sku.name, Location:location}" \
    --output table
    
  echo ""
  echo "📊 Bastion Public IP Information:"
  az network public-ip show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "bastion-pi-localdev-pip" \
    --query "{Name:name, IpAddress:ipAddress, AllocationMethod:publicIPAllocationMethod}" \
    --output table
    
  echo ""
  echo "🔗 Access Instructions:"
  echo "1. Navigate to the Azure Portal"
  echo "2. Go to your VM: vm-pi-localdev"
  echo "3. Click 'Connect' → 'Bastion'"
  echo "4. Use SSH authentication with your private key"
  echo "5. Username: azureuser"
else
  echo "❌ Azure Bastion deployment failed."
fi
