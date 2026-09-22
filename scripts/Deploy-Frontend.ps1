[CmdletBinding()]
param()
. "$PSScriptRoot/Common.ps1"
$maintenance = Enter-LabMaintenance
try {
$null = Get-Lab
if (Test-Path (Join-Path $script:StateDirectory 'web-outage.json')) { throw 'Restore the active web outage before deploying.' }
$manifest = & "$PSScriptRoot/Get-FrontendManifest.ps1"
$path = Join-Path $script:StateDirectory 'frontend.json'
Write-LabJson $path $manifest
Invoke-LabKube -File $path -Command 'kubectl apply -f frontend.json && kubectl -n srelab rollout status deployment/web --timeout=240s'
Write-Host 'Frontend deployed to the private web Service behind the public shop gateway. See SHOP.md for HTTPS access; Start-DemoViewer.ps1 is optional for the private dashboard.'
} finally { $maintenance.Dispose() }