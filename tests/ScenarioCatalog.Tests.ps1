$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/ScenarioCatalog.ps1"
if ($script:ScenarioCatalog.Count -ne 28) { throw 'Expected 28 additional scenarios.' }
foreach ($name in $script:ScenarioCatalog.Keys) {
    $definition = Get-ScenarioDefinition $name
    $wrapper = Join-Path $PSScriptRoot "../scripts/scenarios/$name.ps1"
    if (-not (Test-Path $wrapper) -or (Get-Content $wrapper -Raw) -notmatch "-Scenario $name\s+@PSBoundParameters") { throw "Missing or misrouted wrapper: $name" }
    if (-not $definition.kind -or -not $definition.check -or -not $definition.title) { throw "Incomplete scenario: $name" }
    if ($definition['path'] -and $definition.path -notmatch '^/providers/Microsoft.Network/') { throw "Unscoped network target: $name" }
    if ($definition['target'] -and $definition.target -notin @('client', 'backend', 'blob', 'vault')) { throw "Unexpected target: $name" }
}
$rejected = $false
try { Get-ScenarioDefinition 'not-a-lab-scenario' } catch { $rejected = $true }
if (-not $rejected) { throw 'Unknown scenario was accepted.' }
Write-Host 'Scenario catalog: 28 definitions and invalid-name rejection passed.'