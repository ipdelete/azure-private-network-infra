#!/bin/bash

# ─────────────────────────────────────────────
# 🔍 PKI Function App — Deployment Validation
# ─────────────────────────────────────────────
# Validates the Function App (RA) deployment:
# 1. Infrastructure exists
# 2. VNet integration
# 3. Managed identity + RBAC
# 4. App settings populated
# 5. Function registered

set -uo pipefail

# 🔧 Configuration
RESOURCE_GROUP="aet-pi-localdev-es2-tst4"
FUNC_APP_NAME="func-pki-ra"
PKI_SA_NAME="sapki4x6ipx4ntpsqk"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    echo -n "  $label: "
    if "$@" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ pass${NC}"
        ((PASS++))
    else
        echo -e "${RED}❌ fail${NC}"
        ((FAIL++))
    fi
}

check_output() {
    local label="$1"
    local expected="$2"
    shift 2
    echo -n "  $label: "
    local result
    result=$("$@" 2>/dev/null) || true
    if echo "$result" | grep -qi "$expected"; then
        echo -e "${GREEN}✅ $result${NC}"
        ((PASS++))
    else
        echo -e "${RED}❌ expected '$expected', got '$result'${NC}"
        ((FAIL++))
    fi
}

echo -e "${BLUE}🔍 PKI Function App — Deployment Validation${NC}"
echo "════════════════════════════════════════════════════"
echo "📅 $(date)"
echo "🏗️  Resource Group: $RESOURCE_GROUP"
echo "⚡ Function App:   $FUNC_APP_NAME"
echo ""

# ─────────────────────────────────────────────
# 1. Infrastructure Exists
# ─────────────────────────────────────────────
echo -e "${YELLOW}1️⃣  Infrastructure${NC}"

check "Function App exists" \
    az functionapp show -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" --query name -o tsv

check_output "Function App SKU" "FlexConsumption" \
    az functionapp show -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" --query "properties.sku" -o tsv

FUNC_SA_NAME=$(az functionapp config appsettings list \
    -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" \
    --query "[?name=='AzureWebJobsStorage__accountName'].value | [0]" -o tsv 2>/dev/null || echo "")

if [ -n "$FUNC_SA_NAME" ]; then
    check "Runtime storage account exists" \
        az storage account show -g "$RESOURCE_GROUP" -n "$FUNC_SA_NAME" --query name -o tsv
else
    echo -e "  Runtime storage account: ${RED}❌ could not determine name${NC}"
    ((FAIL++))
fi

check "App Service Plan exists" \
    az appservice plan show -g "$RESOURCE_GROUP" -n "${FUNC_APP_NAME}-plan" --query name -o tsv

echo ""

# ─────────────────────────────────────────────
# 2. VNet Integration
# ─────────────────────────────────────────────
echo -e "${YELLOW}2️⃣  VNet Integration${NC}"

VNET_INTEGRATION=$(az functionapp vnet-integration list \
    -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" \
    --query '[0].vnetResourceId' -o tsv 2>/dev/null || echo "")

if echo "$VNET_INTEGRATION" | grep -q "vnet-pki-lab"; then
    echo -e "  VNet integration: ${GREEN}✅ connected to vnet-pki-lab${NC}"
    ((PASS++))
else
    echo -e "  VNet integration: ${RED}❌ not connected (got: $VNET_INTEGRATION)${NC}"
    ((FAIL++))
fi

if echo "$VNET_INTEGRATION" | grep -q "funcSubnet"; then
    echo -e "  Subnet: ${GREEN}✅ funcSubnet${NC}"
    ((PASS++))
else
    echo -e "  Subnet: ${RED}❌ expected funcSubnet${NC}"
    ((FAIL++))
fi

echo ""

# ─────────────────────────────────────────────
# 3. Managed Identity + RBAC
# ─────────────────────────────────────────────
echo -e "${YELLOW}3️⃣  Managed Identity & RBAC${NC}"

PRINCIPAL_ID=$(az functionapp identity show \
    -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" \
    --query principalId -o tsv 2>/dev/null || echo "")

if [ -n "$PRINCIPAL_ID" ] && [ "$PRINCIPAL_ID" != "null" ]; then
    echo -e "  System-assigned identity: ${GREEN}✅ $PRINCIPAL_ID${NC}"
    ((PASS++))
else
    echo -e "  System-assigned identity: ${RED}❌ not assigned${NC}"
    ((FAIL++))
fi

if [ -n "$PRINCIPAL_ID" ] && [ "$PRINCIPAL_ID" != "null" ]; then
    # Check RBAC on PKI storage account
    PKI_SA_ID=$(az storage account show -g "$RESOURCE_GROUP" -n "$PKI_SA_NAME" --query id -o tsv 2>/dev/null || echo "")
    if [ -n "$PKI_SA_ID" ]; then
        PKI_ROLE=$(az role assignment list \
            --scope "$PKI_SA_ID" \
            --assignee "$PRINCIPAL_ID" \
            --query "[].roleDefinitionName" -o tsv 2>/dev/null || echo "")
        if echo "$PKI_ROLE" | grep -qi "Blob Data Contributor"; then
            echo -e "  RBAC on PKI SA: ${GREEN}✅ Storage Blob Data Contributor${NC}"
            ((PASS++))
        else
            echo -e "  RBAC on PKI SA: ${RED}❌ missing Blob Data Contributor (got: $PKI_ROLE)${NC}"
            ((FAIL++))
        fi
    else
        echo -e "  RBAC on PKI SA: ${RED}❌ PKI storage account not found${NC}"
        ((FAIL++))
    fi

    # Check RBAC on function runtime storage account
    if [ -n "$FUNC_SA_NAME" ]; then
        FUNC_SA_ID=$(az storage account show -g "$RESOURCE_GROUP" -n "$FUNC_SA_NAME" --query id -o tsv 2>/dev/null || echo "")
        if [ -n "$FUNC_SA_ID" ]; then
            FUNC_ROLE=$(az role assignment list \
                --scope "$FUNC_SA_ID" \
                --assignee "$PRINCIPAL_ID" \
                --query "[].roleDefinitionName" -o tsv 2>/dev/null || echo "")
            if echo "$FUNC_ROLE" | grep -qi "Blob Data Owner"; then
                echo -e "  RBAC on runtime SA: ${GREEN}✅ Storage Blob Data Owner${NC}"
                ((PASS++))
            else
                echo -e "  RBAC on runtime SA: ${RED}❌ missing Blob Data Owner (got: $FUNC_ROLE)${NC}"
                ((FAIL++))
            fi
        fi
    fi
fi

echo ""

# ─────────────────────────────────────────────
# 4. App Settings
# ─────────────────────────────────────────────
echo -e "${YELLOW}4️⃣  App Settings${NC}"

REQUIRED_SETTINGS=(
    "STEP_CA_URL"
    "STEP_CA_FINGERPRINT"
    "STEP_CA_PROVISIONER"
    "STEP_CA_PASSWORD"
    "PKI_STORAGE_ACCOUNT_NAME"
    "AzureWebJobsStorage__accountName"
)

APP_SETTINGS=$(az functionapp config appsettings list \
    -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" \
    --query "[].name" -o tsv 2>/dev/null || echo "")

for setting in "${REQUIRED_SETTINGS[@]}"; do
    if echo "$APP_SETTINGS" | grep -q "^${setting}$"; then
        echo -e "  $setting: ${GREEN}✅ present${NC}"
        ((PASS++))
    else
        echo -e "  $setting: ${RED}❌ missing${NC}"
        ((FAIL++))
    fi
done

echo ""

# ─────────────────────────────────────────────
# 5. Function Registered
# ─────────────────────────────────────────────
echo -e "${YELLOW}5️⃣  Function Registration${NC}"

FUNCTIONS=$(az functionapp function list \
    -g "$RESOURCE_GROUP" -n "$FUNC_APP_NAME" \
    --query "[].name" -o tsv 2>/dev/null || echo "")

if echo "$FUNCTIONS" | grep -q "SignCsr"; then
    echo -e "  SignCsr function: ${GREEN}✅ registered${NC}"
    ((PASS++))
else
    echo -e "  SignCsr function: ${YELLOW}⚠️  not registered (code may not be deployed yet)${NC}"
    # Warning, not failure — infra can be valid without code deployed
fi

echo ""

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo "════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}✅ All $TOTAL checks passed${NC}"
else
    echo -e "${RED}❌ $FAIL of $TOTAL checks failed${NC}"
    exit 1
fi
