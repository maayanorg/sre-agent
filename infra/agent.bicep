targetScope = 'resourceGroup'

param location string = resourceGroup().location
param tags object
param workspaceId string
param operatorObjectId string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-srelab-agent-swc-001'
  location: location
  tags: tags
}

resource reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, 'Reader')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  }
}

resource monitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, 'Monitoring Reader')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-srelab-agent-swc-001'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceId
    IngestionMode: 'LogAnalytics'
  }
}

resource agent 'Microsoft.App/agents@2026-01-01' = {
  name: 'sre-srelab-swc-001'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    defaultModel: { provider: 'MicrosoftFoundry', name: 'Automatic' }
    actionConfiguration: {
      accessLevel: 'Low'
      identity: identity.id
      mode: 'Review'
    }
    knowledgeGraphConfiguration: {
      identity: identity.id
      managedResources: [resourceGroup().id]
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: insights.properties.AppId
        connectionString: insights.properties.ConnectionString
      }
    }
  }
  dependsOn: [reader, monitoringReader]
}

output agentId string = agent.id
output identityPrincipalId string = identity.properties.principalId

resource logReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, 'Log Analytics Reader')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
  }
}

resource administrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: agent
  name: guid(agent.id, operatorObjectId, 'SREAdministrator')
  properties: {
    principalId: operatorObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e79298df-d852-4c6d-84f9-5d13249d1e55')
  }
}
