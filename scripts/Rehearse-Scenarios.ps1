[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string[]]$Scenario, [ValidateRange(1, 30)][int]$VerificationAttempts = 8)
. "$PSScriptRoot/ScenarioCatalog.ps1"
foreach ($name in $Scenario) { $null = Get-ScenarioDefinition $name }
foreach ($name in $Scenario) {
    if (-not $PSCmdlet.ShouldProcess($name, 'Inject, verify failure, restore and verify recovery')) { continue }
    $failure = $null
    try {
        & "$PSScriptRoot/Invoke-LabScenario.ps1" -Scenario $name -Action Inject
        for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
            try { & "$PSScriptRoot/Test-Scenario.ps1" -Scenario $name; break }
            catch { if ($attempt -eq $VerificationAttempts) { throw }; Write-Warning "Symptom not conclusive yet ($attempt/$VerificationAttempts): $_" }
        }
    } catch { $failure = $_ }
    finally {
        $stateFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.state/active-incident.json'
        if (Test-Path $stateFile) {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($state.scenario -eq $name) {
                for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
                    try { & "$PSScriptRoot/Invoke-LabScenario.ps1" -Scenario $name -Action Reset; break }
                    catch { if ($attempt -eq $VerificationAttempts) { throw }; Write-Warning "Recovery not conclusive yet ($attempt/$VerificationAttempts): $_" }
                }
            }
        }
    }
    if ($failure) { throw $failure }
    Write-Host "REHEARSED AND RECOVERED: $name"
}