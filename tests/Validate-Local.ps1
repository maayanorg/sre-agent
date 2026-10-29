$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failures = @()
foreach ($file in Get-ChildItem $root -Recurse -Filter '*.ps1') {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in $parseErrors) { $failures += "$($file.Name): $($parseError.Message)" }
}
foreach ($source in @('workload/server.js', 'workload/shop.cjs', 'workload/frontend/shop-proxy.cjs', 'workload/frontend/server.cjs', 'workload/frontend/viewer.cjs', 'scripts/preview-shop.cjs', 'scripts/seed-shop.cjs')) {
    & node --check (Join-Path $root $source)
    if ($LASTEXITCODE -ne 0) { $failures += "Node syntax validation failed: $source" }
}
& node --test (Join-Path $root 'tests/frontend.test.cjs') (Join-Path $root 'tests/operations.test.cjs') (Join-Path $root 'tests/shop.test.cjs') (Join-Path $root 'tests/shop-proxy.test.cjs') (Join-Path $root 'tests/seed-shop.test.cjs')
if ($LASTEXITCODE -ne 0) { $failures += 'Frontend behavior tests failed.' }
foreach ($test in @('ScenarioCatalog.Tests.ps1', 'ScenarioEngine.Tests.ps1', 'PublicShop.Tests.ps1', 'LabMetadata.Tests.ps1')) {
    try { & (Join-Path $PSScriptRoot $test) } catch { $failures += "$test : $_" }
}
if ($failures.Count) { throw ($failures -join "`n") }
Write-Host 'PowerShell parsing, Node syntax and frontend behavior checks passed.'