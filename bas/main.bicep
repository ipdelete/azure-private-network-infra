targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 📦 Azure Bastion Deployment Template
// ─────────────────────────────────────────────

// 🔧 Parameters
@description('Bastion host name')
param bastionHostName string = 'bastion-pi-localdev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual Network Name')
param vnetName string = 'vnet-pi-localdev'

@description('Bastion Subnet Name (must be AzureBastionSubnet)')
param bastionSubnetName string = 'AzureBastionSubnet'

@description('Bastion SKU')
@allowed(['Basic', 'Standard'])
param bastionSku string = 'Standard'

// 🔧 Variables
var publicIpName = '${bastionHostName}-pip'

// 📡 Reference existing VNet and Bastion subnet
resource existingVNet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
  
  resource bastionSubnet 'subnets' existing = {
    name: bastionSubnetName
  }
}

// 🌐 Public IP for Bastion (required)
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

// 🏰 Azure Bastion Host
resource bastionHost 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: bastionHostName
  location: location
  sku: {
    name: bastionSku
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: existingVNet::bastionSubnet.id
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

// 🚀 Outputs
output bastionHostId string = bastionHost.id
output bastionHostName string = bastionHost.name
output bastionPublicIpAddress string = bastionPublicIp.properties.ipAddress
