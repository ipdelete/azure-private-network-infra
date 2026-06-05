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

@secure()
@description('Provisioner password for step-ca RA authentication')
param stepCaProvisionerPassword string

@description('step-ca URL (private IP)')
param stepCaUrl string = 'https://10.1.1.4'

@description('step-ca root CA fingerprint')
param stepCaFingerprint string

@description('step-ca provisioner name')
param stepCaProvisionerName string = 'ra-provisioner'

// 🔧 Variables
var funcStorageAccountName = 'safunc${uniqueString(resourceGroup().id)}'
var appServicePlanName = '${functionAppName}-plan'
var deployContainerName = 'app-package'

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
// ⚡ App Service Plan (Flex Consumption)
// ─────────────────────────────────────────────

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
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
    virtualNetworkSubnetId: vnet::funcSubnet.id
    functionAppConfig: {
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 10
        instanceMemoryMB: 2048
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${funcStorageAccount.name}.blob.${environment().suffixes.storage}/${deployContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: funcStorageAccount.name
        }
        {
          name: 'PKI_STORAGE_ACCOUNT_NAME'
          value: pkiStorageAccountName
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
          name: 'STEP_CA_PASSWORD'
          value: stepCaProvisionerPassword
        }
      ]
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

// ─────────────────────────────────────────────
// 🔐 RBAC — Function App → PKI Storage Account
// ─────────────────────────────────────────────

// Storage Blob Data Contributor on the PKI SA (read CSRs, write certs)
resource pkiStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(pkiStorageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: pkiStorageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
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
