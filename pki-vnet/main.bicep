targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 🌐 PKI Lab Virtual Network
// ─────────────────────────────────────────────
// Deploys the network foundation for the PKI lab:
// • VNet with CA, Function App, and Storage subnets
// • NAT Gateway for CA VM outbound access
// • NSGs with least-privilege rules per subnet

param vnetName string = 'vnet-pki-lab'
param vnetAddressSpace string = '10.1.0.0/16'
param caSubnetAddressPrefix string = '10.1.1.0/24'
param funcSubnetAddressPrefix string = '10.1.2.0/24'
param storageSubnetAddressPrefix string = '10.1.3.0/24'

var location = resourceGroup().location

// ─────────────────────────────────────────────
// 🌐 NAT Gateway (outbound for CA VM)
// ─────────────────────────────────────────────

resource natGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: 'pip-natgateway-${vnetName}'
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

resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = {
  name: 'natgw-${vnetName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natGatewayPublicIp.id
      }
    ]
    idleTimeoutInMinutes: 4
  }
}

// ─────────────────────────────────────────────
// 🔒 Network Security Groups
// ─────────────────────────────────────────────

resource caSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-caSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowBastionSSH'
        properties: {
          description: 'Allow SSH from Bastion subnet in the existing VNet (via peering)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.2.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowStepCaFromFunc'
        properties: {
          description: 'Allow HTTPS traffic from Function App subnet to step-ca'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: funcSubnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource funcSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-funcSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpsToCA'
        properties: {
          description: 'Allow Function App to reach step-ca on HTTPS'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: funcSubnetAddressPrefix
          destinationAddressPrefix: caSubnetAddressPrefix
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          description: 'Allow Function App to reach storage private endpoints'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 1100
          direction: 'Outbound'
        }
      }
    ]
  }
}

resource storageSubnetNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-pkiStorageSubnet'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowVNetInbound'
        properties: {
          description: 'Allow VNet traffic inbound for private endpoints'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          description: 'Allow Storage service outbound traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
  }
}

// ─────────────────────────────────────────────
// 🌐 Virtual Network
// ─────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressSpace]
    }
    subnets: [
      {
        name: 'caSubnet'
        properties: {
          addressPrefix: caSubnetAddressPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: caSubnetNsg.id
          }
          natGateway: {
            id: natGateway.id
          }
        }
      }
      {
        name: 'funcSubnet'
        properties: {
          addressPrefix: funcSubnetAddressPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: funcSubnetNsg.id
          }
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'pkiStorageSubnet'
        properties: {
          addressPrefix: storageSubnetAddressPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: storageSubnetNsg.id
          }
        }
      }
    ]
  }
}

// ─────────────────────────────────────────────
// 📊 Outputs
// ─────────────────────────────────────────────

output vnetId string = vnet.id
output vnetName string = vnet.name
output caSubnetId string = vnet.properties.subnets[0].id
output funcSubnetId string = vnet.properties.subnets[1].id
output storageSubnetId string = vnet.properties.subnets[2].id
output natGatewayId string = natGateway.id
output natGatewayPublicIpAddress string = natGatewayPublicIp.properties.ipAddress
