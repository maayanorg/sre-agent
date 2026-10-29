targetScope = 'resourceGroup'

param location string = 'swedencentral'
param sshPublicKey string
param operatorObjectId string
param vmSize string = 'Standard_B1ms'
param aksVmSize string = 'Standard_D2s_v4'
param existingVmNames array = []
param aksSubnetNsgId string = ''
param privateEndpointSubnetNsgId string = ''
param tags object = {
  Project: 'SRE-Day'
  Purpose: 'IncidentResponseLab'
  Environment: 'Demo'
  Owner: 'mluxemburg'
  Lifecycle: 'ReusableEvent'
  ManagedBy: 'Bicep'
}

var suffix = uniqueString(resourceGroup().id)
var readerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-srelab-swc-001'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: 1 }
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-srelab-workload-swc-001'
  location: location
  tags: tags
  properties: {
    securityRules: [{
      name: 'AllowLabHttp'
      properties: {
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRanges: ['8080', '8081']
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: '*'
      }
    }]
  }
}

resource routes 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-srelab-client-swc-001'
  location: location
  tags: tags
  properties: { routes: [] }
}

resource egressIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-srelab-egress-swc-001'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-srelab-egress-swc-001'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [{ id: egressIp.id }]
  }
}

resource network 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-srelab-services-swc-001'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.70.0.0/16'] }
    subnets: [
      {
        name: 'snet-client'
        properties: {
          addressPrefix: '10.70.1.0/24'
          networkSecurityGroup: { id: nsg.id }
          routeTable: { id: routes.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-backend'
        properties: {
          addressPrefix: '10.70.2.0/24'
          networkSecurityGroup: { id: nsg.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: union({
          addressPrefix: '10.70.3.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          defaultOutboundAccess: false
        }, empty(privateEndpointSubnetNsgId) ? {} : { networkSecurityGroup: { id: privateEndpointSubnetNsgId } })
      }
    ]
  }
}

resource aksNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-srelab-aks-swc-001'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.71.0.0/16'] }
    subnets: [{
      name: 'snet-aks'
      properties: union({ addressPrefix: '10.71.0.0/22' }, empty(aksSubnetNsgId) ? {} : { networkSecurityGroup: { id: aksSubnetNsgId } })
    }]
  }
}

resource peerToAks 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: network
  name: 'services-to-aks'
  properties: {
    remoteVirtualNetwork: { id: aksNetwork.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource peerToServices 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: aksNetwork
  name: 'aks-to-services'
  properties: {
    remoteVirtualNetwork: { id: network.id }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
  }
}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-srelab-workload-swc-001'
  location: location
  tags: tags
}

resource appReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, appIdentity.id, 'Reader')
  properties: {
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: readerRole
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stsrelab${suffix}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'lab'
  properties: { publicAccess: 'None' }
}

resource blobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storage
  name: guid(storage.id, appIdentity.id, 'BlobReader')
  properties: {
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-srelab-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}

resource vaultReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, appIdentity.id, 'SecretsUser')
  properties: {
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}

resource blobZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}
resource vaultZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}
resource labZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'srelab.internal'
  location: 'global'
  tags: tags
}

module dnsLinks './dns-links.bicep' = {
  params: {
    zoneNames: [blobZone.name, vaultZone.name, labZone.name]
    networkIds: [network.id, aksNetwork.id]
    tags: tags
  }
}

resource backendRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: labZone
  name: 'backend'
  properties: { ttl: 30, aRecords: [{ ipv4Address: '10.70.2.4' }] }
}

module endpoints './endpoints.bicep' = {
  params: {
    location: location
    tags: tags
    subnetId: '${network.id}/subnets/snet-private-endpoints'
    targets: [
      { name: 'blob', id: storage.id, groupId: 'blob', zoneId: blobZone.id }
      { name: 'vault', id: vault.id, groupId: 'vault', zoneId: vaultZone.id }
    ]
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-srelab-vm-swc-001'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      syslog: [{
        name: 'syslog'
        streams: ['Microsoft-Syslog']
        facilityNames: ['daemon', 'user', 'local0']
        logLevels: ['Debug', 'Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency']
      }]
      performanceCounters: [{
        name: 'perf'
        streams: ['Microsoft-Perf']
        samplingFrequencyInSeconds: 60
        counterSpecifiers: ['\\Processor(_Total)\\% Processor Time', '\\Memory\\% Used Memory', '\\Logical Disk(*)\\% Used Space']
      }]
    }
    destinations: { logAnalytics: [{ name: 'workspace', workspaceResourceId: workspace.id }] }
    dataFlows: [{ streams: ['Microsoft-Syslog', 'Microsoft-Perf'], destinations: ['workspace'] }]
  }
}

module client './vm.bicep' = {
  params: {
    name: 'vm-srelab-client-swc-001'
    includeBootstrap: !contains(existingVmNames, 'vm-srelab-client-swc-001')
    location: location
    tags: tags
    size: vmSize
    sshPublicKey: sshPublicKey
    subnetId: '${network.id}/subnets/snet-client'
    privateIp: '10.70.1.4'
    identityId: appIdentity.id
    identityClientId: appIdentity.properties.clientId
    dcrId: dcr.id
    role: 'client'
    storageName: storage.name
    vaultName: vault.name
    resourceGroupId: resourceGroup().id
  }
}
module backend './vm.bicep' = {
  params: {
    name: 'vm-srelab-backend-swc-001'
    includeBootstrap: !contains(existingVmNames, 'vm-srelab-backend-swc-001')
    location: location
    tags: tags
    size: vmSize
    sshPublicKey: sshPublicKey
    subnetId: '${network.id}/subnets/snet-backend'
    privateIp: '10.70.2.4'
    identityId: appIdentity.id
    identityClientId: appIdentity.properties.clientId
    dcrId: dcr.id
    role: 'backend'
    storageName: storage.name
    vaultName: vault.name
    resourceGroupId: resourceGroup().id
  }
}

resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-srelab-aks-swc-001'
  location: location
  tags: tags
}
resource aksNetworkRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aksNetwork
  name: guid(aksNetwork.id, aksIdentity.id, 'NetworkContributor')
  properties: {
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
  }
}
resource aks 'Microsoft.ContainerService/managedClusters@2024-10-01' = {
  name: 'aks-srelab-swc-001'
  location: location
  tags: tags
  sku: { name: 'Base', tier: 'Free' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${aksIdentity.id}': {} }
  }
  properties: {
    dnsPrefix: 'aks-srelab-${suffix}'
    nodeResourceGroup: 'rg-srelab-aksnodes-swedencentral-001'
    enableRBAC: true
    disableLocalAccounts: true
    aadProfile: { managed: true, enableAzureRBAC: true, tenantID: subscription().tenantId }
    apiServerAccessProfile: { enablePrivateCluster: true, enablePrivateClusterPublicFQDN: false }
    agentPoolProfiles: [{
      name: 'system'
      count: 1
      vmSize: aksVmSize
      osDiskSizeGB: 64
      osDiskType: 'Managed'
      osType: 'Linux'
      type: 'VirtualMachineScaleSets'
      mode: 'System'
      maxPods: 30
      vnetSubnetID: '${aksNetwork.id}/subnets/snet-aks'
      nodeLabels: { purpose: 'srelab' }
      tags: tags
    }]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'calico'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.72.0.0/16'
      dnsServiceIP: '10.72.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
    addonProfiles: {
      omsagent: { enabled: true, config: { logAnalyticsWorkspaceResourceID: workspace.id, useAADAuth: 'true' } }
    }
    autoUpgradeProfile: { upgradeChannel: 'patch', nodeOSUpgradeChannel: 'NodeImage' }
  }
  dependsOn: [aksNetworkRole]
}

resource aksAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aks
  name: guid(aks.id, operatorObjectId, 'ClusterAdmin')
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')
  }
}

module agent './agent.bicep' = {
  params: { location: location, tags: tags, workspaceId: workspace.id, operatorObjectId: operatorObjectId }
}

module monitoring './monitoring.bicep' = {
  params: { location: location, tags: tags, workspaceId: workspace.id, aksId: aks.id, vaultName: vault.name, storageName: storage.name }
}

output lab object = {
  subscriptionId: subscription().subscriptionId
  resourceGroup: resourceGroup().name
  location: location
  workspaceId: workspace.id
  workspaceCustomerId: workspace.properties.customerId
  agentId: agent.outputs.agentId
  agentPrincipalId: agent.outputs.identityPrincipalId
  aksId: aks.id
  storageName: storage.name
  vaultName: vault.name
  appIdentityId: appIdentity.id
  appPrincipalId: appIdentity.properties.principalId
  appClientId: appIdentity.properties.clientId
  readerAssignmentId: appReader.id
  blobAssignmentId: blobReader.id
  vaultAssignmentId: vaultReader.id
}
