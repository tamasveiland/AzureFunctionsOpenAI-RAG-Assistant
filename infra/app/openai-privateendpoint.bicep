// Parameters
@description('Specifies the name of the virtual network.')
param virtualNetworkName string

@description('Specifies the name of the subnet which contains the virtual machine.')
param subnetName string

@description('Specifies the location.')
param location string = resourceGroup().location

param openAiResourceId string

param tags object = {}


// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' existing = {
  name: virtualNetworkName
}

resource openaiPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-08-01' = {
  name: 'openaiPrivateEndpoint'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'openaipvtendpoint'
        properties: {
          privateLinkServiceId: openAiResourceId
          groupIds: [
            'account'
          ]
        }
      }
    ]
    subnet: {
      id: '${vnet.id}/subnets/${subnetName}'
    }
  }
}

// Private DNS Zones
resource openAIPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.openai.azure.com'
  location: 'global'
  tags: tags
  properties: {}
  dependsOn: [
    vnet
  ]
}

resource openaiPrivateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: openAIPrivateDnsZone
  name: uniqueString(vnet.id)
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource openaiPrivateDnsZoneGroupName 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-01-01' = {
  parent: openaiPrivateEndpoint
  name: 'openaiPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: openAIPrivateDnsZone.id
        }
      }
    ]
  }
}
