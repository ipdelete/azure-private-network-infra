#!/bin/bash

# ─────────────────────────────────────────────
# 📦 Bicep Deployment Script: Resource Group
# ─────────────────────────────────────────────

# 🔧 Configurable variables
LOCATION="centralus"                    # Deployment location
BICEP_FILE="main.bicep"               # Bicep template file
PARAM_FILE="main.parameters.json"    # Parameter file
DEPLOYMENT_NAME="rg-deploy-$(date +%s)"  # Unique deployment name

# 🚀 Run the deployment
echo "Starting deployment: $DEPLOYMENT_NAME"

az deployment sub create \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --location "$LOCATION" \
  --name "$DEPLOYMENT_NAME"

# ✅ Check result
if [ $? -eq 0 ]; then
  echo "✅ Deployment succeeded."
else
  echo "❌ Deployment failed."
fi