$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/Common.ps1"
$script:StateDirectory = Join-Path ([IO.Path]::GetTempPath()) "srelab-metadata-$([guid]::NewGuid())"
$script:deploymentState = 'Failed'
$script:customerId = 'fixture-workspace'
function Assert-Lab {}
function Invoke-Az {
    param($Arguments)
    return @{ properties = @{ provisioningState = $script:deploymentState; outputs = @{ lab = @{ value = 'live-output' } } } }
}
function Invoke-LabRest {
    param($Id, $Api)
    return @{ properties = @{ customerId = $script:customerId } }
}
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        return
    }
    throw "Expected rejection: $Message"
}
$cached = @{
    subscriptionId = $script:Subscription
    resourceGroup = $script:ResourceGroup
    agentId = "$script:GroupId/providers/Microsoft.App/agents/fixture"
    workspaceId = "$script:GroupId/providers/Microsoft.OperationalInsights/workspaces/fixture"
    aksId = "$script:GroupId/providers/Microsoft.ContainerService/managedClusters/fixture"
    workspaceCustomerId = $script:customerId
}
try {
    Assert-Rejected { Get-Lab -AllowCachedMetadata } 'Baseline deployment state'
    Write-LabJson (Join-Path $script:StateDirectory 'lab.json') $cached
    Assert-Rejected { Get-Lab } 'Baseline deployment state'
    $warnings = @()
    $lab = Get-Lab -AllowCachedMetadata -WarningVariable warnings -WarningAction SilentlyContinue
    if ($lab.agentId -ne $cached.agentId -or $warnings.Count -ne 1) { throw 'Cache recovery must return metadata and warn.' }
    $script:deploymentState = 'Running'
    Assert-Rejected { Get-Lab -AllowCachedMetadata } 'Baseline deployment state'
    $script:deploymentState = 'Succeeded'
    if ((Get-Lab) -ne 'live-output') { throw 'Successful deployments must use live outputs.' }
    $script:deploymentState = 'Failed'
    $script:customerId = 'different-workspace'
    Assert-Rejected { Get-Lab -AllowCachedMetadata } 'customer ID does not match'
    $script:customerId = $cached.workspaceCustomerId
    $cached.subscriptionId = 'different-subscription'
    Write-LabJson (Join-Path $script:StateDirectory 'lab.json') $cached
    Assert-Rejected { Get-Lab -AllowCachedMetadata } 'does not match the configured'
    $cached.subscriptionId = $script:Subscription
    $cached.agentId = '/subscriptions/other/resourceGroups/other/providers/Microsoft.App/agents/fixture'
    Write-LabJson (Join-Path $script:StateDirectory 'lab.json') $cached
    Assert-Rejected { Get-Lab -AllowCachedMetadata } 'outside lab scope'
    Write-Host 'Lab metadata: explicit recovery, default guard, deployment states and cache scope checks passed.'
} finally {
    if (Test-Path $script:StateDirectory) { Remove-Item $script:StateDirectory -Recurse -Force }
}