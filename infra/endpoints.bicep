param location string
param tags object
param subnetId string
type endpointTarget = { name: string, id: string, groupId: string, zoneId: string }
param targets endpointTarget[]

resource endpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for target in targets: {
  name: 'pe-srelab-${target.name}-swc-001'
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [{
      name: target.name
      properties: { privateLinkServiceId: target.id, groupIds: [target.groupId] }
    }]
  }
}]
resource groups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = [for (target, index) in targets: {
  parent: endpoints[index]
  name: 'default'
  properties: { privateDnsZoneConfigs: [{ name: target.name, properties: { privateDnsZoneId: target.zoneId } }] }
}]
