param location string
param tags object
param workspaceId string
param aksId string
param vaultName string
param storageName string

resource aks 'Microsoft.ContainerService/managedClusters@2024-10-01' existing = { name: last(split(aksId, '/')) }
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = { name: vaultName }
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = { name: storageName }
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = { parent: storage, name: 'default' }

resource aksLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'srelab-logs'
  scope: aks
  properties: {
    workspaceId: workspaceId
    logAnalyticsDestinationType: 'Dedicated'
    logs: [{ category: 'kube-audit-admin', enabled: true }, { category: 'kube-apiserver', enabled: true }]
  }
}
resource vaultLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'srelab-logs'
  scope: vault
  properties: { workspaceId: workspaceId, logAnalyticsDestinationType: 'Dedicated', logs: [{ category: 'AuditEvent', enabled: true }] }
}
resource blobLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'srelab-logs'
  scope: blob
  properties: { workspaceId: workspaceId, logAnalyticsDestinationType: 'Dedicated', logs: [{ category: 'StorageRead', enabled: true }] }
}

var checks = [
  { name: 'dependency-failure', query: 'Syslog | where ProcessName == "srelab-probe" | where SyslogMessage contains "SRELAB" and SyslogMessage !contains "status=200"', threshold: 0, severity: 2 }
  { name: 'pod-failure', query: 'KubePodInventory | where Namespace == "srelab" | where PodStatus !in ("Running", "Succeeded") or ContainerStatusReason in ("CrashLoopBackOff", "ImagePullBackOff", "OOMKilled")', threshold: 0, severity: 2 }
  { name: 'telemetry-missing', query: 'Heartbeat | where Computer in ("client", "backend") | summarize LastSeen=max(TimeGenerated) by Computer | where LastSeen < ago(5m)', threshold: 0, severity: 2 }
]
resource alerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for check in checks: {
  name: 'alert-srelab-${check.name}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'SRE lab: ${check.name}'
    severity: check.severity
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [workspaceId]
    autoMitigate: true
    skipQueryValidation: true
    criteria: { allOf: [{ query: check.query, timeAggregation: 'Count', operator: 'GreaterThan', threshold: check.threshold, failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 } }] }
  }
}]

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'srelab-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'SRE Lab - Incident Evidence'
    category: 'workbook'
    sourceId: workspaceId
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        { type: 3, name: 'Dependency probes', content: { version: 'KqlItem/1.0', query: 'Syslog | where TimeGenerated > ago(30m) | where ProcessName == "srelab-probe" | project TimeGenerated, Computer, SyslogMessage', size: 0, queryType: 0, resourceType: 'microsoft.operationalinsights/workspaces' } }
        { type: 3, name: 'Pod state', content: { version: 'KqlItem/1.0', query: 'KubePodInventory | where TimeGenerated > ago(30m) | where Namespace == "srelab" | summarize arg_max(TimeGenerated, *) by Name | project TimeGenerated, Name, PodStatus, ContainerStatusReason', size: 0, queryType: 0, resourceType: 'microsoft.operationalinsights/workspaces' } }
      ]
      isLocked: false
    })
  }
}
