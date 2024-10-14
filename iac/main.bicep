targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Id of the user or app to assign application roles')
param principalId string = ''

@minLength(1)
@maxLength(64)
@description('Application name')
param applicationName string

param keyVaultName string = ''
param applicationInsightsName string = ''
param logAnalyticsName string = ''
param appServicePlanName string = ''
param appServiceName string = ''
param acrName string = ''
param acrSku string = ''
param createEventSubscription bool = false
param functionName string = 'ProcessBlobEvents'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, applicationName, environmentName, location))
var tags = { 'app-name': applicationName, 'env-name': environmentName }

/////////// Common ///////////

// Resource Group
resource rg_common 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}management_${location}'
  location: location
  tags: tags
}

// Store secrets in a keyvault
module keyVault './core/host/keyvault.bicep' = {
  name: 'keyvault_common'
  scope: rg_common
  params: {
    name: !empty(keyVaultName)
      ? keyVaultName
      : '${abbrs.keyVaults}${applicationName}-${environmentName}-${resourceToken}'
    location: location
    tags: tags
  }
}
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan_common'
  scope: rg_common
  params: {
    name: !empty(appServicePlanName)
      ? appServicePlanName
      : '${abbrs.webServerFarms}common-${environmentName}-${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'Y1'
      tier: 'Dynamic'
    }
  }
}

// Monitor application with Azure Monitor
module monitoring './core/host/monitoring.bicep' = {
  name: 'monitoring_common'
  scope: rg_common
  params: {
    applicationInsightsName: !empty(applicationInsightsName)
      ? applicationInsightsName
      : '${abbrs.monitoringAppInsights}common-${environmentName}-${resourceToken}'
    logAnalyticsName: !empty(logAnalyticsName)
      ? logAnalyticsName
      : '${abbrs.monitoringLogAnalytics}common-${environmentName}-${resourceToken}'
    location: location
    tags: tags
  }
}

/////////// END Common ///////////

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${applicationName}_${environmentName}_${location}'
  location: location
  tags: tags
}
/////////// Fontend App ///////////

module appservice './core/host/appservice.bicep' = {
  name: '${applicationName}-fe-appservice'
  scope: rg
  params: {
    name: !empty(appServiceName)
      ? appServiceName
      : '${abbrs.webSitesAppService}${applicationName}-fe-${environmentName}-${resourceToken}'
    location: location
    tags: tags
    appServicePlanId: appServicePlan.outputs.id
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    keyVaultName: keyVault.outputs.name
    runtimeName: 'node'
    runtimeVersion: '14'
  }
}

output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_LOCATION string = location

output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output STORAGE_ACCOUNT_ID string = storageAccount.outputs.id
output STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output STORAGE_CONTAINER_NAME array = storageAccount.outputs.containerNames
output EVENT_GRID_NAME string = eventGrid.outputs.systemTopicName
output APPLICATION_INSIGHTS_NAME string = monitoring.outputs.applicationInsightsName
output LOG_ANALYTICS_NAME string = monitoring.outputs.logAnalyticsName
output APP_SERVICE_PLAN_NAME string = appServicePlan.outputs.name
output FUNCTION_APP_ID string = functions.outputs.id
output FUNCTION_APP_NAME string = functions.outputs.name
output FUNCTION_APP_HOST_NAME string = functions.outputs.uri
output FUNCTION_APP_PRINCIPAL_ID string = functions.outputs.identityPrincipalId
output RESOURCE_TOKEN string = resourceToken
output AZURE_RESOURCE_GROUP_NAME string = rg.name
