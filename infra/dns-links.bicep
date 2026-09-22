param zoneNames array
param networkIds array
param tags object

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' existing = [for zoneName in zoneNames: {
  name: zoneName
}]

resource linksServices 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, index) in zoneNames: {
  parent: zones[index]
  name: 'link-services'
  location: 'global'
  tags: tags
  properties: { registrationEnabled: false, virtualNetwork: { id: networkIds[0] } }
}]

resource linksAks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, index) in zoneNames: {
  parent: zones[index]
  name: 'link-aks'
  location: 'global'
  tags: tags
  properties: { registrationEnabled: false, virtualNetwork: { id: networkIds[1] } }
}]
