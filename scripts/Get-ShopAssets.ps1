[CmdletBinding()]
param()
$root = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $root '.state/shop-assets'
$null = New-Item -ItemType Directory -Path $directory -Force
$assets = Get-Content (Join-Path $root 'workload/shop-assets.json') -Raw | ConvertFrom-Json
foreach ($asset in $assets) {
    $destination = Join-Path $directory "$($asset.id).jpg"
    if (-not (Test-Path $destination)) { Invoke-WebRequest -Uri $asset.source -OutFile $destination -TimeoutSec 30 }
    $bytes = [IO.File]::ReadAllBytes($destination)
    if ($bytes.Length -lt 100 -or $bytes.Length -gt 100000 -or $bytes[0] -ne 255 -or $bytes[1] -ne 216) { throw "Invalid or oversized JPEG: $($asset.id)" }
}
Write-Host 'Four product JPEGs are ready in .state/shop-assets. No Azure resources were changed.'