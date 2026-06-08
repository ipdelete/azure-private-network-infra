#!/bin/bash
set -e

# ─────────────────────────────────────────────
# ⚡ Bicep Deployment Script: PKI Lab Function App (RA)
#
# TWO-PASS DEPLOY (rationale):
#   Pass 1 (enableKeyVaultReferences=false) — creates the Function App,
#     system-assigned MI, and the Key Vault Secrets User role assignment.
#     This warms the MI so KV references can resolve.
#   Pass 2 (enableKeyVaultReferences=true) — adds the @Microsoft.KeyVault(...)
#     app settings, then restarts the app to force resolution.
#
# Prerequisites before pass 1:
#   • pki-logs and pki-kv have been deployed.
#   • main.parameters.json has been updated with the real
#     logAnalyticsWorkspaceId and keyVaultName outputs.
# Prerequisites before pass 2:
#   • The KV bootstrap (pki-kv/README.md) has seeded the three secrets:
#     step-ca-provisioner-password, step-ca-provisioner-jwk, step-ca-root-cert.
# ─────────────────────────────────────────────

# 🔧 Configurable variables
RESOURCE_GROUP_NAME="aet-pi-localdev-es2-tst4"
BICEP_FILE="main.bicep"
PARAM_FILE="main.parameters.json"
TS=$(date +%s)
FUNCTION_APP_NAME=$(jq -r '.parameters.functionAppName.value' "$PARAM_FILE")

# 🚀 Pass 1 — create app + identity + KV role (no KV-ref settings yet)
PASS1_NAME="pki-func-deploy-pass1-$TS"
echo "▶️  Pass 1: $PASS1_NAME  (enableKeyVaultReferences=false)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --parameters enableKeyVaultReferences=false \
  --name "$PASS1_NAME" >/dev/null
echo "✅ Pass 1 complete."

# Give the MI a moment to be visible to Key Vault RBAC
echo "⏳ Sleeping 30s to let MI propagate before adding KV references..."
sleep 30

# 🚀 Pass 2 — add KV-ref settings
PASS2_NAME="pki-func-deploy-pass2-$TS"
echo "▶️  Pass 2: $PASS2_NAME  (enableKeyVaultReferences=true)"
az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --parameters enableKeyVaultReferences=true \
  --name "$PASS2_NAME" >/dev/null
echo "✅ Pass 2 complete."

# 🔁 Restart so KV references are re-resolved cleanly
echo "🔁 Restarting Function App..."
az functionapp restart -g "$RESOURCE_GROUP_NAME" -n "$FUNCTION_APP_NAME" >/dev/null
echo "✅ Done."

