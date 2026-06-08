targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 📊 PKI Lab — Shared Log Analytics Workspace
// ─────────────────────────────────────────────
// Single workspace consumed by pki-sa, pki-kv, and pki-func diagnostic
// settings. Lives in its own module to avoid circular module dependencies
// between those three modules.

// 🔧 Parameters
@description('Location for the workspace')
param location string = resourceGroup().location

@description('Log Analytics workspace name')
param workspaceName string = 'log-pki-lab'

@description('Workspace SKU')
param sku string = 'PerGB2018'

@description('Retention in days')
param retentionInDays int = 30

// 📊 Workspace
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
  }
}

// 📊 Outputs
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
