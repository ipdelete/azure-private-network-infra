#!/bin/bash

# ─────────────────────────────────────────────
# 📦 Bicep Deployment Script: VNet
# ─────────────────────────────────────────────

# 🔧 Configurable variables
RESOURCE_GROUP_NAME="aet-pi-localdev-es2-tst3"  # Resource group name
BICEP_FILE="main.bicep"               # Bicep template file
PARAM_FILE="main.parameters.json"    # Parameter file
DEPLOYMENT_NAME="vnet-deploy-$(date +%s)"  # Unique deployment name

# 🚀 Run the deployment
echo "Starting deployment: $DEPLOYMENT_NAME"

az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --name "$DEPLOYMENT_NAME"

# ✅ Check result
if [ $? -eq 0 ]; then
  echo "✅ Deployment succeeded."
else
  echo "❌ Deployment failed."
fi