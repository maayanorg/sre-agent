[CmdletBinding()]
param([ValidateRange(1024, 65535)][int]$Port = 8090)
. "$PSScriptRoot/Common.ps1"
Assert-Lab
$page = & "$PSScriptRoot/Get-DemoSnapshot.ps1" -Page
if ($page -match '<title>Fieldnote \| Shop</title>') {
	$healthPage = & "$PSScriptRoot/Get-DemoSnapshot.ps1" -HealthPage
} elseif ($page -match '<title>SRE Day \| Service Health</title>') {
	$healthPage = $page
	Write-Warning 'Azure still serves the health dashboard. The shop has not been deployed.'
} else { throw 'Expected AKS shop or health dashboard was not returned.' }
if ($healthPage -notmatch '<title>SRE Day \| Service Health</title>') { throw 'Expected health page was not returned.' }
$null = New-Item -ItemType Directory -Path $script:StateDirectory -Force
$page | Set-Content (Join-Path $script:StateDirectory 'frontend-page.html') -Encoding utf8
$healthPage | Set-Content (Join-Path $script:StateDirectory 'health-page.html') -Encoding utf8
& node (Join-Path $script:Root 'workload/frontend/viewer.cjs') $Port
if ($LASTEXITCODE -ne 0) { throw 'Demo viewer stopped with an error.' }