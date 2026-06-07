targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 💾 PKI Lab — Storage Account for CSR/Cert Exchange
// ─────────────────────────────────────────────
// Deploys a blob storage account with:
// • Two containers: csr/ and certs/
// • Private endpoints in both the PKI and existing VNets
// • Separate private DNS zones so each non-peered VNet resolves to its local private endpoint
// • No public network access

// 🔧 Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account name prefix')
param storageAccountPrefix string = 'sapki'

@description('PKI VNet name (new VNet)')
param pkiVnetName string = 'vnet-pki-lab'

@description('PKI storage subnet name')
param pkiStorageSubnetName string = 'pkiStorageSubnet'

@description('Existing VNet name')
param existingVnetName string = 'vnet-pi-localdev'

@description('Existing storage subnet name')
param existingStorageSubnetName string = 'storageSubnet'

@description('Resource group that hosts the PKI VNet private DNS zone')
param pkiDnsResourceGroupName string = 'aet-pki-dns-centralus-tst4'

// 🔧 Variables
var storageAccountName = '${storageAccountPrefix}${uniqueString(resourceGroup().id)}'
var privateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

// ─────────────────────────────────────────────
// 🌐 Reference existing VNets and subnets
// ─────────────────────────────────────────────

resource pkiVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: pkiVnetName

  resource pkiStorageSubnet 'subnets' existing = {
    name: pkiStorageSubnetName
  }
}

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: existingVnetName

  resource existingStorageSubnet 'subnets' existing = {
    name: existingStorageSubnetName
  }
}

// ─────────────────────────────────────────────
// 💾 Storage Account (Blob)
// ─────────────────────────────────────────────

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// ─────────────────────────────────────────────
// 📦 Blob Containers
// ─────────────────────────────────────────────

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource csrContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'csr'
  properties: {
    publicAccess: 'None'
  }
}

resource certsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'certs'
  properties: {
    publicAccess: 'None'
  }
}

// ─────────────────────────────────────────────
// 🔒 Private DNS Zones
// ─────────────────────────────────────────────

resource existingPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

resource dnsLinkExistingVnet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZoneName}-existing-link'
  parent: existingPrivateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: existingVnet.id
    }
  }
}

module pkiPrivateDns './private-dns-zone.bicep' = {
  name: 'pki-blob-private-dns'
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

resource pkiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob-pki'
  location: location
  properties: {
    subnet: {
      id: pkiVnet::pkiStorageSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${storageAccountName}-blob-pki-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource pkiDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: pkiPrivateEndpoint
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
// 🔒 Private Endpoint — Existing VNet
// ─────────────────────────────────────────────

resource existingPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob-existing'
  location: location
  properties: {
    subnet: {
      id: existingVnet::existingStorageSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${storageAccountName}-blob-existing-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource existingDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: existingPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneName
        properties: {
    privateDnsZoneId: existingPrivateDnsZone.id
        }
      }
    ]
  }
}

// ─────────────────────────────────────────────
// 📊 Outputs
// ─────────────────────────────────────────────

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output csrContainerName string = csrContainer.name
output certsContainerName string = certsContainer.name
output existingPrivateDnsZoneId string = existingPrivateDnsZone.id
output pkiPrivateDnsZoneId string = pkiPrivateDns.outputs.privateDnsZoneId
output pkiPrivateEndpointId string = pkiPrivateEndpoint.id
output existingPrivateEndpointId string = existingPrivateEndpoint.id
