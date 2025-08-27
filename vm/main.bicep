targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// 📦 Virtual Machine Deployment Template
// ─────────────────────────────────────────────

// 🔧 Parameters
param vmName string
param adminUsername string
param vmSize string = 'Standard_B2s'
param location string = resourceGroup().location
param vnetName string = 'vnet-pi-localdev'
param subnetName string = 'vmSubnet'

@secure()
@description('SSH public key for the admin user (ssh-rsa format)')
param adminPublicKey string

// 🔧 Variables
var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'

// � Reference existing VNet and subnet
resource existingVNet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
  
  resource vmSubnet 'subnets' existing = {
    name: subnetName
  }
}

// 🌐 Network Interface Card
resource networkInterface 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: existingVNet::vmSubnet.id
          }
        }
      }
    ]
  }
}

// 💻 Red Hat Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        enableVMAgentPlatformUpdates: false
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'RedHat'
        offer: 'RHEL'
        sku: '9_4'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

// 🚀 Outputs
output vmId string = virtualMachine.id
output privateIPAddress string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
output vmName string = virtualMachine.name
output networkInterfaceId string = networkInterface.id
