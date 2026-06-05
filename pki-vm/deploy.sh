#!/bin/bash

# ─────────────────────────────────────────────
# 🏛️ Bicep Deployment Script: PKI Lab CA VM
# ─────────────────────────────────────────────

# 🔧 Configurable variables
RESOURCE_GROUP_NAME="aet-pi-localdev-es2-tst4"
BICEP_FILE="main.bicep"
PARAM_FILE="main.parameters.json"
DEPLOYMENT_NAME="pki-vm-deploy-$(date +%s)"

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
