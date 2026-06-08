targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 🔐 PKI Lab — Private Key Vault
// ─────────────────────────────────────────────
// Houses the step-ca provisioner password, encrypted JWK, and root CA cert
// used by func-pki-ra. No public network access. Accessible only via a
// private endpoint in the PKI VNet (the Function App is VNet-integrated
// into pki-lab). RBAC authorization is required.

// 🔧 Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Key Vault name prefix')
param keyVaultNamePrefix string = 'kvpki'

@description('PKI VNet name (new VNet)')
param pkiVnetName string = 'vnet-pki-lab'

@description('PKI storage subnet name (hosts the KV private endpoint)')
param pkiStorageSubnetName string = 'pkiStorageSubnet'

@description('Resource group that hosts the PKI VNet private DNS zone')
param pkiDnsResourceGroupName string = 'aet-pki-dns-centralus-tst4'

@description('Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string

@description('Tenant ID for the Key Vault')
param tenantId string = subscription().tenantId

// 🔧 Variables
var keyVaultName = '${keyVaultNamePrefix}${uniqueString(resourceGroup().id)}'
var privateDnsZoneName = 'privatelink.vaultcore.azure.net'

// ─────────────────────────────────────────────
// 🌐 Reference existing PKI VNet/subnet
// ─────────────────────────────────────────────

resource pkiVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: pkiVnetName

  resource pkiStorageSubnet 'subnets' existing = {
    name: pkiStorageSubnetName
  }
}

// ─────────────────────────────────────────────
// 🔐 Key Vault
// ─────────────────────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// ─────────────────────────────────────────────
// 🔒 Private DNS Zone (in PKI DNS RG, linked to PKI VNet)
// ─────────────────────────────────────────────

module pkiPrivateDns '../pki-sa/private-dns-zone.bicep' = {
  name: 'pki-kv-private-dns'
  scope: resourceGroup(pkiDnsResourceGroupName)
  params: {
    privateDnsZoneName: privateDnsZoneName
    virtualNetworkId: pkiVnet.id
    linkName: '${privateDnsZoneName}-pki-link'
  }
}

// ─────────────────────────────────────────────
// 🔒 Private Endpoint — PKI VNet
// ─────────────────────────────────────────────

resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${keyVaultName}-vault-pki'
  location: location
  properties: {
    subnet: {
      id: pkiVnet::pkiStorageSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${keyVaultName}-vault-pki-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource kvDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: kvPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneName
        properties: {
          privateDnsZoneId: pkiPrivateDns.outputs.privateDnsZoneId
        }
      }
    ]
  }
}

// ─────────────────────────────────────────────
// 📊 Diagnostics
// ─────────────────────────────────────────────

resource kvDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'kv-pki-diagnostics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ─────────────────────────────────────────────
// 📊 Outputs
// ─────────────────────────────────────────────

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
