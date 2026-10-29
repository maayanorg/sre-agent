[CmdletBinding()]
param([Parameter(Mandatory)][string]$Scenario, [ValidateSet('Injected', 'Recovered')][string]$Expected = 'Injected')
. "$PSScriptRoot/ScenarioEngine.ps1"
$definition = Get-ScenarioDefinition $Scenario
$null = Get-Lab -AllowCachedMetadata
$operational = $definition.check -in @('operator', 'cpu', 'memory', 'ama')
if ($operational) {
    $snapshot = & "$PSScriptRoot/Get-OperationsSnapshot.ps1" -AllowCachedMetadata | ConvertFrom-Json
    $check = @($snapshot.checks | Where-Object id -eq $definition.check)
    if ($check.Count -ne 1 -or $check[0].state -eq 'unknown') { throw 'No conclusive operational evidence. Check observation permissions and retry.' }
    $failed = $check[0].state -eq 'failed'
} else {
    $snapshot = & "$PSScriptRoot/Get-DemoSnapshot.ps1" | ConvertFrom-Json
    $age = ([DateTime]::UtcNow - ([DateTime]$snapshot.observedAt).ToUniversalTime()).TotalSeconds
    if ($age -lt 0 -or $age -gt 120) { throw 'Observation is stale or future-dated.' }
    $check = @($snapshot.checks | Where-Object id -eq $definition.check)
    if ($snapshot.overall -eq 'unavailable' -and $definition.check -eq 'web') { $failed = $true }
    elseif ($check.Count -eq 1) { $failed = -not $check[0].healthy }
    else { throw 'No conclusive application evidence. Observation path may be unavailable.' }
}
if (($Expected -eq 'Injected') -ne $failed) { throw "Expected $Expected symptom for $Scenario has not been observed. Allow propagation, then retry Verify or Reset; recovery state is retained." }
$evidence = @{ scenario = $Scenario; expected = $Expected; verifiedAt = [DateTime]::UtcNow.ToString('o'); check = $definition.check; snapshot = $snapshot }
Write-LabJson (Join-Path $script:StateDirectory "verification/$Scenario-$Expected.json") $evidence
Write-Host "$Scenario / $Expected verified from $($definition.check) observation."