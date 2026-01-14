@description('The name of the Azure OpenAI service')
param openAIServiceName string

@description('The name of the AI Hub')
param aiHubName string = 'aihub-${uniqueString(resourceGroup().id)}'

@description('The name of the AI Project')
param aiProjectName string = 'aiproject-${uniqueString(resourceGroup().id)}'

@description('Location for the Azure OpenAI service')
param location string = resourceGroup().location

@description('SKU name for the Azure OpenAI service')
@allowed([
  'S0'
])
param skuName string = 'S0'

@description('The name of the GPT model deployment')
param deploymentName string = 'gpt4-deployment'

@description('The GPT model to deploy')
@allowed([
  'gpt-4'
  'gpt-4-32k'
  'gpt-4-turbo'
  'gpt-4o'
])
param modelName string = 'gpt-4o'

@description('The version of the model to deploy')
param modelVersion string = '2024-05-13'

@description('The capacity for the model deployment')
param modelCapacity int = 10

// Create Storage Account for AI Hub
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

// Create Key Vault for AI Hub
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    accessPolicies: []
  }
}

// Create Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Create Azure OpenAI Service
resource cognitiveService 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: openAIServiceName
  location: location
  kind: 'OpenAI'
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: openAIServiceName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false // Explicitly enable API key authentication
    networkAcls: {
      defaultAction: 'Allow'
    }
    apiProperties: {
      statisticsEnabled: false
    }
  }
}

// Deploy the GPT model
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: cognitiveService
  name: deploymentName
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

// Create AI Hub (Machine Learning Workspace)
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiHubName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Hub'
  properties: {
    friendlyName: aiHubName
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
    publicNetworkAccess: 'Enabled'
  }
}

// Create AI Project
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiProjectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Project'
  properties: {
    friendlyName: aiProjectName
    hubResourceId: aiHub.id
    publicNetworkAccess: 'Enabled'
  }
}

// Note: Connection will be created manually or through the portal after deployment
// to ensure proper API key authentication settings

// Outputs
output endpoint string = cognitiveService.properties.endpoint
output serviceName string = cognitiveService.name
output resourceId string = cognitiveService.id
@secure()
output apiKey string = cognitiveService.listKeys().key1
output deploymentName string = modelDeployment.name
output aiHubName string = aiHub.name
output aiProjectName string = aiProject.name
output aiHubId string = aiHub.id
output aiProjectId string = aiProject.id
