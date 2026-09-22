[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Scenario,
    [ValidateSet('Inject', 'Status', 'Reset', 'Verify')][string]$Action = 'Status',
    [ValidateSet('Injected', 'Recovered')][string]$Expected = 'Injected'
)
. "$PSScriptRoot/ScenarioEngine.ps1"
$definition = Get-ScenarioDefinition $Scenario
$lab = Get-Lab
$null = New-Item -ItemType Directory -Path $script:StateDirectory -Force
$statePath = Join-Path $script:StateDirectory 'active-incident.json'
$lock = [IO.File]::Open((Join-Path $script:StateDirectory 'incident.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $saved = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 100 } else { $null }
    if ($Action -eq 'Status') {
        [pscustomobject]@{ scenario = $Scenario; description = $definition.title; activeScenario = $(if ($saved) { $saved.scenario } else { 'None' }); phase = $(if ($saved) { $saved.phase } else { 'Healthy baseline expected' }) }
        & "$PSScriptRoot/Inspect-Scenario.ps1" -Scenario $Scenario
        & "$PSScriptRoot/Get-DemoSnapshot.ps1"
        return
    }
    if ($Action -eq 'Verify') {
        & "$PSScriptRoot/Test-Scenario.ps1" -Scenario $Scenario -Expected $Expected
        return
    }
    if (Test-Path (Join-Path $script:StateDirectory 'web-outage.json')) { throw 'Restore the existing web outage first.' }
    if ($Action -eq 'Inject') {
        if ($saved) { throw "An incident is already recorded: $($saved.scenario). Reset it first." }
        if (-not $PSCmdlet.ShouldProcess($definition.title, 'Capture state and inject a scoped lab fault')) { return }
        $baseline = & "$PSScriptRoot/Get-DemoSnapshot.ps1" | ConvertFrom-Json
        if ($baseline.overall -ne 'healthy' -or @($baseline.checks | Where-Object healthy -eq $true).Count -ne 6) { throw 'All six application checks must be healthy before injection.' }
        $saved = New-ScenarioState -Scenario $Scenario -Lab $lab
        Write-LabJson $statePath $saved
        Set-ScenarioMutation $saved
        $saved.phase = 'Injected'
        Write-LabJson $statePath $saved
        Write-Host 'Mutation completed. Verify the symptom separately; DNS/RBAC/telemetry may need propagation time.'
    } else {
        if (-not $saved -or $saved.scenario -ne $Scenario -or $saved.groupId -ne $script:GroupId -or $saved.version -ne 1) { throw 'No matching recovery state in this workspace.' }
        if (-not $PSCmdlet.ShouldProcess($definition.title, 'Restore captured state')) { return }
        if ($saved.phase -ne 'RestoredAwaitingVerification') {
            if ($saved.kind -eq 'Endpoint' -and -not $saved.ContainsKey('endpointRecovery')) {
                $saved.endpointRecovery = Get-EndpointRecovery -Target $definition.target
                $saved.endpointRecovery.replaceRejected = $true
                Write-LabJson $statePath $saved
            }
            Set-ScenarioMutation $saved -Restore
            $saved.phase = 'RestoredAwaitingVerification'
            Write-LabJson $statePath $saved
        }
        & "$PSScriptRoot/Test-Scenario.ps1" -Scenario $Scenario -Expected Recovered
        $stamp = ([DateTime]$saved.timestamp).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
        $history = Join-Path $script:StateDirectory "history/$stamp-$Scenario.json"
        $saved.phase = 'Recovered'; $saved.recoveredAt = [DateTime]::UtcNow.ToString('o')
        Write-LabJson $history $saved
        Remove-Item $statePath
        Write-Host 'Original state restored and symptom recovery verified.'
    }
} finally { $lock.Dispose() }