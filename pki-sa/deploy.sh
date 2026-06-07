#!/bin/bash

# ─────────────────────────────────────────────
# 💾 Bicep Deployment Script: PKI Lab Storage Account
# ─────────────────────────────────────────────

# 🔧 Configurable variables
RESOURCE_GROUP_NAME="aet-pi-localdev-es2-tst4"
PKI_DNS_RESOURCE_GROUP_NAME="aet-pki-dns-centralus-tst4"
BICEP_FILE="main.bicep"
PARAM_FILE="main.parameters.json"
DEPLOYMENT_NAME="pki-sa-deploy-$(date +%s)"

# 🚀 Run the deployment
echo "Starting deployment: $DEPLOYMENT_NAME"

LOCATION=$(az group show --name "$RESOURCE_GROUP_NAME" --query location -o tsv)
az group create --name "$PKI_DNS_RESOURCE_GROUP_NAME" --location "$LOCATION" --output none

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
