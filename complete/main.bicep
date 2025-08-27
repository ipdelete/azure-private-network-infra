targetScope = 'subscription'

// ─────────────────────────────────────────────
// 📦 Azure Private Network Infrastructure - Complete Deployment
// ─────────────────────────────────────────────
// This template deploys the entire secure Azure infrastructure:
// • Resource Group
// • Virtual Network with NAT Gateway and NSGs
// • Storage Account with Private Endpoint
// • NFS 4.1 File Share
// • Red Hat Linux VM with automated NFS mounting
// • Azure Bastion Host for secure access

// 🔧 Parameters
@description('Resource group name')
param rgName string = 'aet-pi-localdev-es2-tst4'

@description('Location for all resources')
param location string = 'eastus2'

@description('Virtual network name')
param vnetName string = 'vnet-pi-localdev'

@description('Virtual network address space')
param vnetAddressSpace string = '10.0.0.0/16'

@description('VM subnet address prefix')
param vmSubnetAddressPrefix string = '10.0.1.0/24'

@description('Bastion subnet address prefix')
param bastionSubnetAddressPrefix string = '10.0.2.0/24'

@description('Storage subnet address prefix')
param storageSubnetAddressPrefix string = '10.0.3.0/24'

@description('Storage account name prefix')
param storageAccountPrefix string = 'sapifile'

@description('NFS Share name')
param nfsShareName string = 'nfsshare'

@description('NFS Share quota in GB')
param shareQuotaGb int = 100

@description('Virtual machine name')
param vmName string = 'vm-pi-localdev'

@description('VM admin username')
param adminUsername string = 'azureuser'

@description('VM size')
param vmSize string = 'Standard_B2s'

@secure()
@description('SSH public key for the admin user (ssh-rsa format)')
param adminPublicKey string

@description('Bastion host name')
param bastionHostName string = 'bastion-pi-localdev'

@description('Bastion SKU')
@allowed(['Basic', 'Standard'])
param bastionSku string = 'Basic'

// 🔧 Variables
var storageAccountName = '${storageAccountPrefix}${uniqueString(subscription().subscriptionId, rgName)}'

// ─────────────────────────────────────────────
// 🏗️ Resource Group Deployment
// ─────────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  location: location
  name: rgName
  tags: {
    'created-by': 'ianphil'
    'deployment-type': 'complete-infrastructure'
  }
}

// ─────────────────────────────────────────────
// 🌐 Virtual Network Deployment
// ─────────────────────────────────────────────
module vnetDeployment '../vnet/main.bicep' = {
  scope: rg
  name: 'vnet-deployment'
  params: {
    vnetName: vnetName
    vnetAddressSpace: vnetAddressSpace
    vmSubnetAddressPrefix: vmSubnetAddressPrefix
    bastionSubnetAddressPrefix: bastionSubnetAddressPrefix
    storageSubnetAddressPrefix: storageSubnetAddressPrefix
  }
}

// ─────────────────────────────────────────────
// 💾 Storage Account Deployment
// ─────────────────────────────────────────────
module storageDeployment '../sa/main.bicep' = {
  scope: rg
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountPrefix: storageAccountPrefix
    vnetResourceGroupName: rgName
    vnetName: vnetName
    storageSubnetName: 'storageSubnet'
  }
  dependsOn: [
    vnetDeployment
  ]
}

// ─────────────────────────────────────────────
// 📁 NFS File Share Deployment
// ─────────────────────────────────────────────
module nfsDeployment '../nfs/main.bicep' = {
  scope: rg
  name: 'nfs-deployment'
  params: {
    storageAccountPrefix: storageAccountPrefix
    nfsShareName: nfsShareName
    shareQuotaGb: shareQuotaGb
  }
  dependsOn: [
    storageDeployment
  ]
}

// ─────────────────────────────────────────────
// 💻 Virtual Machine Deployment
// ─────────────────────────────────────────────
module vmDeployment '../vm/main.bicep' = {
  scope: rg
  name: 'vm-deployment'
  params: {
    vmName: vmName
    adminUsername: adminUsername
    vmSize: vmSize
    location: location
    vnetName: vnetName
    subnetName: 'vmSubnet'
    adminPublicKey: adminPublicKey
    storageAccountPrefix: storageAccountPrefix
    nfsShareName: nfsShareName
  }
  dependsOn: [
    nfsDeployment
  ]
}

// ─────────────────────────────────────────────
// 🏰 Azure Bastion Deployment
// ─────────────────────────────────────────────
module bastionDeployment '../bas/main.bicep' = {
  scope: rg
  name: 'bastion-deployment'
  params: {
    bastionHostName: bastionHostName
    location: location
    vnetName: vnetName
    bastionSubnetName: 'AzureBastionSubnet'
    bastionSku: bastionSku
  }
  dependsOn: [
    vnetDeployment
  ]
}

// ─────────────────────────────────────────────
// 📊 Outputs
// ─────────────────────────────────────────────
output resourceGroupName string = rg.name
output resourceGroupId string = rg.id
output location string = location

// Network outputs
output vnetId string = vnetDeployment.outputs.vnetId
output vnetName string = vnetDeployment.outputs.vnetName
output vmSubnetId string = vnetDeployment.outputs.vmSubnetId
output bastionSubnetId string = vnetDeployment.outputs.bastionSubnetId
output storageSubnetId string = vnetDeployment.outputs.storageSubnetId
output natGatewayPublicIpAddress string = vnetDeployment.outputs.natGatewayPublicIpAddress

// Storage outputs
output storageAccountName string = storageDeployment.outputs.storageAccountName
output storageAccountId string = storageDeployment.outputs.storageAccountId

// NFS outputs
output nfsShareName string = nfsDeployment.outputs.nfsShareName
output nfsMountPath string = nfsDeployment.outputs.nfsMountPath

// VM outputs
output vmId string = vmDeployment.outputs.vmId
output vmName string = vmDeployment.outputs.vmName
output vmPrivateIPAddress string = vmDeployment.outputs.privateIPAddress

// Bastion outputs
output bastionHostId string = bastionDeployment.outputs.bastionHostId
output bastionHostName string = bastionDeployment.outputs.bastionHostName
output bastionPublicIpAddress string = bastionDeployment.outputs.bastionPublicIpAddress

// Connection information
output connectionInstructions object = {
  accessMethod: 'Azure Portal → Virtual Machines → ${vmName} → Connect → Bastion'
  username: adminUsername
  authMethod: 'SSH Private Key'
  nfsMountLocation: '/mount/${storageAccountName}/${nfsShareName}'
  bastionPublicIP: bastionDeployment.outputs.bastionPublicIpAddress
  vmPrivateIP: vmDeployment.outputs.privateIPAddress
}

// Cloud-init validation commands
output validationCommands object = {
  cloudInitStatus: 'sudo cloud-init status'
  cloudInitLogs: 'sudo cat /var/log/cloud-init.log'
  nfsMount: 'df -h | grep nfs'
  nfsAccess: 'ls -la /mount/${storageAccountName}/${nfsShareName}'
  testWrite: 'echo "Hello from VM" > /mount/${storageAccountName}/${nfsShareName}/test.txt'
}
