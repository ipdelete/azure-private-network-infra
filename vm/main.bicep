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

@description('Storage account name prefix (must match the one used in sa deployment)')
param storageAccountPrefix string = 'sapifile'

@description('NFS Share name')
param nfsShareName string = 'nfsshare'

@description('PKI storage account name (for CSR/cert exchange)')
param pkiStorageAccountName string = ''

// 🔧 Variables
var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'
var storageAccountName = '${storageAccountPrefix}${uniqueString(resourceGroup().id)}'
var mountPath = '/mount/${storageAccountName}/${nfsShareName}'

// Cloud-init script to install aznfs, mount NFS share, and install azcopy
var cloudInitScript = base64('#cloud-config\nyum_repos:\n  packages-microsoft-prod:\n    name: packages-microsoft-prod\n    baseurl: https://packages.microsoft.com/yumrepos/microsoft-rhel9.0-prod\n    enabled: true\n    gpgcheck: true\n    gpgkey: https://packages.microsoft.com/keys/microsoft.asc\nruncmd:\n  - |\n    for i in 1 2 3; do\n      dnf install -y --disablerepo="rhel-*-eus-*" curl rpm aznfs && break\n      sleep 15\n    done\n  - mkdir -p ${mountPath}\n  - mount -t aznfs ${storageAccountName}.file.${environment().suffixes.storage}:/${storageAccountName}/${nfsShareName} ${mountPath} -o vers=4,minorversion=1,sec=sys,nconnect=4\n  - echo "${storageAccountName}.file.${environment().suffixes.storage}:/${storageAccountName}/${nfsShareName} ${mountPath} aznfs vers=4,minorversion=1,sec=sys,nconnect=4 0 0" >> /etc/fstab\n  - chown ${adminUsername}:${adminUsername} ${mountPath}\n  - curl -fsSL https://aka.ms/downloadazcopy-v10-linux | tar xz --strip-components=1 -C /usr/local/bin\n  - chmod +x /usr/local/bin/azcopy')

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
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: cloudInitScript
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
output principalId string = virtualMachine.identity.principalId

// ─────────────────────────────────────────────
// 🔐 RBAC — VM Managed Identity → PKI Storage Account
// ─────────────────────────────────────────────

resource pkiStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (!empty(pkiStorageAccountName)) {
  name: pkiStorageAccountName
}

// Storage Blob Data Contributor on the PKI SA (upload CSRs, read certs)
resource pkiStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(pkiStorageAccountName)) {
  name: guid(pkiStorageAccount.id, virtualMachine.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: pkiStorageAccount
  properties: {
    principalId: virtualMachine.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}
