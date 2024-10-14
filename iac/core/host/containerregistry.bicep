@description('Provide a globally unique name of your Azure Container Registry')
param name string = ''
@description('Provide a tier of your Azure Container Registry.')
param acrSku string = ''
param location string = resourceGroup().location
param tags object = {}

resource acrResource 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
  }
}

@description('Output the login server property for later use')
output loginServer string = acrResource.properties.loginServer
