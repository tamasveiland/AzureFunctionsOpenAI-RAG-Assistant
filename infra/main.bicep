targetScope = 'subscription'
 
@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string
 
@minLength(1)
@description('Primary location for all resources')
param location string
 
param appServicePlanName string = ''
param resourceGroupName string = ''
param azFunctionName string = ''


@allowed([ 'consumption', 'flexconsumption' ])
param azFunctionHostingPlanType string = 'consumption'
param staticWebsiteName string = ''
 
param searchServiceName string = ''
param searchServiceResourceGroupName string = ''
param searchServiceResourceGroupLocation string = location
 
param searchServiceSkuName string = 'standard'
param searchIndexName string = 'gptkbindex'
 
param storageAccountName string = ''
param storageResourceGroupName string = ''
param storageResourceGroupLocation string = location
param storageContainerName string = 'content'
 
param openAiServiceName string = ''
param openAiResourceGroupName string = ''
 
// OpenAI is only available in these regions
// aligned with region location parameter
@allowed([ 'eastus', 'eastus2', 'canadaeast'])
param openAiResourceGroupLocation string = location
 
param openAiSkuName string = 'S0'
 
param gptDeploymentName string = 'text-embedding-3-small'
param gptModelName string = 'text-embedding-3-small'
param chatGptDeploymentName string = 'chat'
param chatGptModelName string = 'gpt-35-turbo'
 
// @description('Id of the user or app to assign application roles')
// param principalId string = ''
 
var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var shareName = 'openaifiles'
 
// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}
 
resource openAiResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(openAiResourceGroupName)) {
  name: !empty(openAiResourceGroupName) ? openAiResourceGroupName : resourceGroup.name
}
 
resource searchServiceResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(searchServiceResourceGroupName)) {
  name: !empty(searchServiceResourceGroupName) ? searchServiceResourceGroupName : resourceGroup.name
}
 
resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(storageResourceGroupName)) {
  name: !empty(storageResourceGroupName) ? storageResourceGroupName : resourceGroup.name
}

var appServicePlanSkuName = azFunctionHostingPlanType == 'consumption' ? 'Y1' : 'FC1'
var appServicePlanSkuTier = azFunctionHostingPlanType == 'consumption' ? 'Dynamic' : 'FlexConsumption'
// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: resourceGroup
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: appServicePlanSkuName
      tier: appServicePlanSkuTier
    }
  }
}
 
module openAi 'core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: openAiResourceGroup
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: openAiResourceGroupLocation
    tags: tags
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: gptDeploymentName
        model: {
          format: 'OpenAI'
          name: gptModelName
          version: '1'
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: chatGptDeploymentName
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: '0613'
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
    ]
  }
}
 
module searchService 'core/search/search-services.bicep' = {
  name: 'search-service'
  scope: searchServiceResourceGroup
  params: {
    name: !empty(searchServiceName) ? searchServiceName : 'gptkb-${resourceToken}'
    location: searchServiceResourceGroupLocation
    tags: tags
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    sku: {
      name: searchServiceSkuName
    }
    semanticSearch: 'free'
  }
}
 
module storage 'core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: storageResourceGroup
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: storageResourceGroupLocation
    tags: tags
    shareName: shareName
    publicNetworkAccess: 'Enabled'
    sku: {
      name: 'Standard_ZRS'
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 2
    }
    containers: [
      {
        name: storageContainerName
        publicAccess: 'None'
      }
      {
        name: 'deploymentpackage'
        publicAccess: 'None'
      }
    ]
  }
}

module function 'core/host/azfunctions.bicep' = if (azFunctionHostingPlanType == 'consumption') {
  name: 'azf'
  scope: resourceGroup
  params: {
    name: !empty(azFunctionName) ? azFunctionName : '${abbrs.webSitesFunctions}${resourceToken}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    azureOpenaiChatgptDeployment: chatGptDeploymentName
    azureOpenaigptDeployment: gptDeploymentName
    azureOpenaiService: openAi.outputs.name
    azureSearchService: searchService.outputs.name
    appInsightsConnectionString : appInsights.outputs.connectionString
    runtimeName: 'dotnet-isolated'
    runtimeVersion: '8.0'
  }
}

module functionflexconsumption 'app/processor.bicep' = if (azFunctionHostingPlanType == 'flexconsumption') {
  name: 'azfflexconsumption'
  scope: resourceGroup
  params: {
    name: !empty(azFunctionName) ? azFunctionName : '${abbrs.webSitesFunctions}${resourceToken}'
    location: location
    tags: tags
    appServicePlanId: appServicePlan.outputs.id
    shareName: shareName
    runtimeName: 'dotnet-isolated'
    runtimeVersion: '8.0'
    storageAccountName: storage.outputs.name
    appInsightsConnectionString : appInsights.outputs.connectionString
    azureOpenaiChatgptDeployment: chatGptDeploymentName
    azureOpenaigptDeployment: gptDeploymentName
    azureOpenaiService: openAi.outputs.name
    azureSearchService: searchService.outputs.name
     appSettings: {
      }
    //virtualNetworkSubnetId: serviceVirtualNetwork.outputs.appSubnetID
  }
}  
var processorFunctionId = azFunctionHostingPlanType == 'consumption' ? function.outputs.id : functionflexconsumption.outputs.id
var processorAppPrincipalId = azFunctionHostingPlanType == 'consumption' ? function.outputs.identityPrincipalId : functionflexconsumption.outputs.SERVICE_PROCESSOR_IDENTITY_PRINCIPAL_ID
 
module appInsights 'core/monitor/app-insights.bicep' = {
  scope: resourceGroup
  name: 'appinsights'
  params: {
    name: '${abbrs.webSitesFunctions}${resourceToken}'
    location: location
    tags: tags
  }
}

module staticwebsite 'core/host/staticwebsite.bicep' = {
  scope: resourceGroup
  name: 'website'
  params: {
    name: !empty(staticWebsiteName) ? staticWebsiteName : '${abbrs.webStaticSites}${resourceToken}'
    location: location
    sku: 'Standard'
    backendResourceId: processorFunctionId
 
  }
}

module openAiRoleUser 'app/openai-access.bicep' = {
  scope: openAiResourceGroup
  name: 'openai-roles'
  params: {
    principalId: processorAppPrincipalId
    openAiAccountResourceName: openAi.outputs.name
    roleDefinitionIds: ['5e0bd9bd-7b93-4f28-af87-19fc36ad61bd']
  }
}
 
module storageRoleUser 'app/storage-access.bicep' = {
  scope: storageResourceGroup
  name: 'storage-roles'
  params: {
    principalId: processorAppPrincipalId
    roleDefinitionIds: ['b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
                        '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
                        'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
                        '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
                        '8a0f0c08-91a1-4084-bc3d-661d67233fed'
                        'c6a89b2d-59bc-44d0-9896-0f6e12d7b80a'
                        '19e7f393-937e-4f77-808e-94535e297925'
                        '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
                        '76199698-9eea-4c19-bc75-cec21354c6b6'
                        '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb'
                        'aba4ae5f-2193-4029-9191-0cb91df5e314']
    storageAccountName: storage.outputs.name
  }
}
 
module searchRoleUser 'app/search-access.bicep' = {
  scope: searchServiceResourceGroup
  name: 'search-roles'
  params: {
    principalId: processorAppPrincipalId
    roleDefinitionIds: ['7ca78c08-252a-4471-8644-bb5ff32d4ba0', '8ebe5a00-799e-43f5-93ac-243d3dce84a7', '1407120a-92aa-4202-b7e9-c0e197c71c8f']
    searchAccountName: searchService.outputs.name
  }
}
 
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroup.name
 
output AZURE_OPENAI_SERVICE string = openAi.outputs.name
output AZURE_OPENAI_RESOURCE_GROUP string = openAiResourceGroup.name
output AZURE_OPENAI_GPT_DEPLOYMENT string = gptDeploymentName
output AZURE_OPENAI_CHATGPT_DEPLOYMENT string = chatGptDeploymentName
output AZURE_OPENAI_LOCATION string = openAi.outputs.location
 
output AZURE_SEARCH_INDEX string = searchIndexName
output AZURE_SEARCH_SERVICE string = searchService.outputs.name
output AZURE_SEARCH_SERVICE_RESOURCE_GROUP string = searchServiceResourceGroup.name
 
output AZURE_STORAGE_ACCOUNT string = storage.outputs.name
output AZURE_STORAGE_CONTAINER string = storageContainerName
output AZURE_STORAGE_RESOURCE_GROUP string = storageResourceGroup.name
 
output AZURE_STATICWEBSITE_NAME string = staticwebsite.outputs.name
output AZURE_FUNCTION_NAME string = azFunctionHostingPlanType == 'consumption' ? function.outputs.name : functionflexconsumption.outputs.SERVICE_PROCESSOR_NAME
