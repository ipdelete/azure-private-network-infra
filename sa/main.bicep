targetScope = 'resourceGroup'

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account name prefix')
param storageAccountPrefix string = 'sapifile'

@description('Virtual Network Resource Group Name')
param vnetResourceGroupName string = resourceGroup().name

@description('Virtual Network Name')
param vnetName string = 'vnet-pi-localdev'

@description('Storage Subnet Name')
param storageSubnetName string = 'storageSubnet'

// Variables
var storageAccountName = '${storageAccountPrefix}${uniqueString(resourceGroup().id)}'
var privateEndpointName = 'pe-${storageAccountName}-file'
var privateDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'

// Reference to existing VNet
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

// Reference to existing storage subnet
resource storageSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: storageSubnetName
  parent: vnet
}

// Storage Account with FileStorage kind
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'FileStorage'
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: [
        {
          value: '76.204.100.248'
          action: 'Allow'
        }
      ]
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Private DNS Zone for File Storage
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

// Link Private DNS Zone to VNet
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZoneName}-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint for File Storage
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: storageSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for the Private Endpoint
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: privateDnsZoneName
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output privateEndpointId string = privateEndpoint.id
output privateDnsZoneId string = privateDnsZone.id
