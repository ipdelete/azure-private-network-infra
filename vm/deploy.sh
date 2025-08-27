#!/bin/bash

# ─────────────────────────────────────────────
# 📦 Bicep Deployment Script: Red Hat VM
# ─────────────────────────────────────────────

# 🔧 Configurable variables
RESOURCE_GROUP="aet-pi-localdev-es2-tst3"  # Target resource group
BICEP_FILE="main.bicep"                     # Bicep template file
PARAM_FILE="main.parameters.json"          # Parameter file
DEPLOYMENT_NAME="vm-deploy-$(date +%s)"    # Unique deployment name

# 🚀 Run the deployment
echo "Starting Red Hat VM deployment: $DEPLOYMENT_NAME"
echo "Target Resource Group: $RESOURCE_GROUP"

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --name "$DEPLOYMENT_NAME"

# ✅ Check result
if [ $? -eq 0 ]; then
  echo "✅ Red Hat VM deployment succeeded."
  
  # 📊 Display VM info
  echo ""
  echo "📊 VM Information:"
  az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "vm-pi-localdev" \
    --query "{Name:name, Size:hardwareProfile.vmSize, Status:provisioningState, Location:location}" \
    --output table
    
  echo ""
  echo "📊 Network Interface Information:"
  az network nic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "vm-pi-localdev-nic" \
    --query "{Name:name, PrivateIP:ipConfigurations[0].privateIPAddress, Subnet:ipConfigurations[0].subnet.id}" \
    --output table
else
  echo "❌ Red Hat VM deployment failed."
fi