targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 🌐 PKI Lab — Private DNS Zone (pki-lab.local)
// ─────────────────────────────────────────────
// Creates the private DNS zone used so that the Function App in the PKI
// VNet (and the requester VM in the existing VNet) can resolve step-ca
// by name (ca.pki-lab.local) instead of by hardcoded IP. step-ca's TLS
// cert SAN matches this DNS name.

// 🔧 Parameters
@description('Private DNS zone name for the PKI lab')
param privateDnsZoneName string = 'pki-lab.local'

@description('PKI VNet name (new VNet)')
param pkiVnetName string = 'vnet-pki-lab'

@description('Resource group of the PKI VNet')
param pkiVnetResourceGroupName string = resourceGroup().name

@description('Existing VNet name (requester VM)')
param existingVnetName string = 'vnet-pi-localdev'

@description('Resource group of the existing VNet')
param existingVnetResourceGroupName string = resourceGroup().name

@description('Private IP of the step-ca VM (caSubnet)')
param caPrivateIpAddress string = '10.1.1.4'

@description('CA hostname under the zone (record name)')
param caRecordName string = 'ca'

// 🌐 Existing VNets (referenced by id for the links)
resource pkiVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: pkiVnetName
  scope: resourceGroup(pkiVnetResourceGroupName)
}

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: existingVnetName
  scope: resourceGroup(existingVnetResourceGroupName)
}

// 🌐 Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

// 🔗 VNet links (both VNets)
resource pkiVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZoneName}-pki-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: pkiVnet.id
    }
  }
}

resource existingVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${privateDnsZoneName}-existing-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: existingVnet.id
    }
  }
}

// 📍 A record for step-ca
resource caARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: caRecordName
  parent: privateDnsZone
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: caPrivateIpAddress
      }
    ]
  }
}

// 📊 Outputs
output privateDnsZoneId string = privateDnsZone.id
output privateDnsZoneName string = privateDnsZone.name
output caFqdn string = '${caRecordName}.${privateDnsZoneName}'
