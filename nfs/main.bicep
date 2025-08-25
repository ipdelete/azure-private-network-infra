targetScope = 'resourceGroup'

// Parameters
@description('Storage account name prefix (must match the one used in sa deployment)')
param storageAccountPrefix string = 'sapifile'

@description('NFS Share name')
param nfsShareName string = 'nfsshare'

@description('NFS Share quota in GB')
param shareQuotaGb int = 100

// Variables
var storageAccountName = '${storageAccountPrefix}${uniqueString(resourceGroup().id)}'

// Reference to existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// File Services for the storage account
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
}

// NFS 4.1 File Share
resource nfsShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: nfsShareName
  parent: fileServices
  properties: {
    shareQuota: shareQuotaGb
    enabledProtocols: 'NFS'
    rootSquash: 'NoRootSquash'
    accessTier: 'Premium'
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output nfsShareName string = nfsShare.name
output nfsShareId string = nfsShare.id
output nfsMountPath string = '${storageAccount.properties.primaryEndpoints.file}${nfsShareName}'

