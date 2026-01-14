@description('The name of the Azure OpenAI service')
param openAIServiceName string

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
  'gpt-4.1'
])
param modelName string = 'gpt-4o'

@description('The version of the model to deploy')
param modelVersion string = '2024-05-13'

@description('The capacity for the model deployment')
param modelCapacity int = 10

// Create Azure OpenAI Service
resource cognitiveService 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
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
    disableLocalAuth: false
    networkAcls: {
      defaultAction: 'Allow'
    }
    apiProperties: {
      statisticsEnabled: false
    }
  }
}

// Deploy the GPT model
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
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

// Outputs
output endpoint string = cognitiveService.properties.endpoint
output serviceName string = cognitiveService.name
output resourceId string = cognitiveService.id
@secure()
output apiKey string = cognitiveService.listKeys().key1
output deploymentName string = modelDeployment.name
