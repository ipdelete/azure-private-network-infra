targetScope = 'resourceGroup'

// ─────────────────────────────────────────────
// ⚡ PKI Lab — Function App (Registration Authority)
// ─────────────────────────────────────────────
// Deploys an Azure Function App that acts as the RA:
// • Blob trigger on the PKI SA's csr container
// • Calls step-ca to sign CSRs
// • Writes signed certs back to the certs container
// • VNet-integrated into funcSubnet for private CA access

// 🔧 Parameters
param location string = resourceGroup().location
param functionAppName string = 'func-pki-ra'
param vnetName string = 'vnet-pki-lab'
param funcSubnetName string = 'funcSubnet'
param pkiStorageAccountName string

@description('Log Analytics workspace resource ID (from pki-logs module)')
param logAnalyticsWorkspaceId string

@description('Key Vault name housing step-ca secrets (from pki-kv module)')
param keyVaultName string

@description('Key Vault DNS suffix. Defaults to environment().suffixes.keyvaultDns.')
param keyVaultDnsSuffix string = environment().suffixes.keyvaultDns

@description('Toggle Key Vault references on app settings. Pass 1 = false (creates app + MI + role); pass 2 = true (adds KV-ref settings).')
param enableKeyVaultReferences bool = false

@description('step-ca URL (uses pki-lab.local DNS, resolves to CA private IP via privateDnsZone)')
param stepCaUrl string = 'https://ca.pki-lab.local'

@description('step-ca root CA fingerprint (sanity check only — chain validation is authoritative)')
param stepCaFingerprint string

@description('step-ca provisioner name')
param stepCaProvisionerName string = 'ra-provisioner'

@description('CSR allow-list: DNS suffix required for all SANs and CN')
param csrAllowedDnsSuffix string = 'pki-lab.local'

// 🔧 Variables
var funcStorageAccountName = 'safunc${uniqueString(resourceGroup().id)}'
var appServicePlanName = '${functionAppName}-plan'
var deployContainerName = 'app-package'
var keyVaultUri = 'https://${keyVaultName}.${keyVaultDnsSuffix}/'
var baseAppSettings = [
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'dotnet-isolated'
  }
  {
    name: 'AzureWebJobsStorage__accountName'
    value: funcStorageAccount.name
  }
  {
    name: 'AzureWebJobsStorage__blobServiceUri'
    value: 'https://${funcStorageAccount.name}.blob.${environment().suffixes.storage}'
  }
  {
    name: 'AzureWebJobsStorage__queueServiceUri'
    value: 'https://${funcStorageAccount.name}.queue.${environment().suffixes.storage}'
  }
  {
    name: 'AzureWebJobsStorage__tableServiceUri'
    value: 'https://${funcStorageAccount.name}.table.${environment().suffixes.storage}'
  }
  {
    name: 'AzureWebJobsStorage__credential'
    value: 'managedidentity'
  }
  {
    name: 'PKI_STORAGE_ACCOUNT_NAME'
    value: pkiStorageAccountName
  }
  {
    name: 'PkiStorageConnection__blobServiceUri'
    value: 'https://${pkiStorageAccountName}.blob.${environment().suffixes.storage}'
  }
  {
    name: 'PkiStorageConnection__credential'
    value: 'managedidentity'
  }
  {
    name: 'STEP_CA_URL'
    value: stepCaUrl
  }
  {
    name: 'STEP_CA_FINGERPRINT'
    value: stepCaFingerprint
  }
  {
    name: 'STEP_CA_PROVISIONER'
    value: stepCaProvisionerName
  }
  {
    name: 'CSR_ALLOWED_DNS_SUFFIX'
    value: csrAllowedDnsSuffix
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsights.properties.ConnectionString
  }
]
var keyVaultRefSettings = [
  {
    name: 'STEP_CA_PROVISIONER_PASSWORD'
    value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/step-ca-provisioner-password/)'
  }
  {
    name: 'STEP_CA_PROVISIONER_JWK'
    value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/step-ca-provisioner-jwk/)'
  }
  {
    name: 'STEP_CA_ROOT_CERT_PEM'
    value: '@Microsoft.KeyVault(SecretUri=${keyVaultUri}secrets/step-ca-root-cert/)'
  }
]

// ─────────────────────────────────────────────
// 🌐 Reference existing VNet and subnet
// ─────────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName

  resource funcSubnet 'subnets' existing = {
    name: funcSubnetName
  }
}

// ─────────────────────────────────────────────
// 🌐 Reference existing PKI storage account
// ─────────────────────────────────────────────

resource pkiStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: pkiStorageAccountName
}

// ─────────────────────────────────────────────
// 💾 Function App Runtime Storage Account
// ─────────────────────────────────────────────

resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: funcStorageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource funcBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: funcStorageAccount
  name: 'default'
}

resource deployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: funcBlobService
  name: deployContainerName
  properties: {
    publicAccess: 'None'
  }
}

// ─────────────────────────────────────────────
// 📊 Application Insights (workspace-backed)
// ─────────────────────────────────────────────

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${functionAppName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
  }
}

// ─────────────────────────────────────────────
// ⚡ App Service Plan (Elastic Premium)
// ─────────────────────────────────────────────

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
  }
  properties: {
    reserved: true
    maximumElasticWorkerCount: 1
  }
}

// ─────────────────────────────────────────────
// ⚡ Function App
// ─────────────────────────────────────────────

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'
    virtualNetworkSubnetId: vnet::funcSubnet.id
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      alwaysOn: true
      vnetRouteAllEnabled: true
      appSettings: enableKeyVaultReferences ? concat(baseAppSettings, keyVaultRefSettings) : baseAppSettings
    }
  }
}

// ─────────────────────────────────────────────
// 🔐 RBAC — Function App → Function Runtime Storage
// ─────────────────────────────────────────────

// Storage Blob Data Owner on the function runtime SA (for deployment + AzureWebJobsStorage)
resource funcStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccount.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: funcStorageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  }
}

// Storage Queue Data Contributor on the function runtime SA (AzureWebJobsStorage queues)
resource funcStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: funcStorageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  }
}

// Storage Table Data Contributor on the function runtime SA (AzureWebJobsStorage tables)
resource funcStorageTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(funcStorageAccount.id, functionApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: funcStorageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  }
}

// ─────────────────────────────────────────────
// 🔐 RBAC — Function App → PKI Storage Account
// ─────────────────────────────────────────────

// Storage Blob Data Owner on the PKI SA (account-scoped — required by
// identity-based BlobTrigger for receipts/leases, plus reading CSRs and
// writing certs/rejected blobs).
resource pkiStorageBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(pkiStorageAccount.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: pkiStorageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  }
}

// Storage Queue Data Contributor on the PKI SA (account-scoped — required
// by identity-based BlobTrigger to write poison-blob messages).
resource pkiStorageQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(pkiStorageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: pkiStorageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  }
}

// ─────────────────────────────────────────────
// 🔐 RBAC — Function App → Key Vault
// ─────────────────────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

// Key Vault Secrets User on the PKI KV (read secrets via KV references)
resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, '4633458b-17de-4321-9a5d-6b3aab74e0ed')
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-4321-9a5d-6b3aab74e0ed')
  }
}

// ─────────────────────────────────────────────
// 📊 Outputs
// ─────────────────────────────────────────────

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output functionAppPrincipalId string = functionApp.identity.principalId
output funcStorageAccountName string = funcStorageAccount.name
output defaultHostName string = functionApp.properties.defaultHostName
output keyVaultUri string = keyVaultUri
