[CmdletBinding(SupportsShouldProcess)]
param()
. "$PSScriptRoot/Common.ps1"
$lab = Get-Lab
$maintenance = Enter-LabMaintenance
try {
    foreach ($hostname in @("$($lab.storageName).blob.core.windows.net", "$($lab.vaultName).vault.azure.net")) {
        $addresses = [Net.Dns]::GetHostAddresses($hostname)
        if (-not @($addresses | Where-Object { $_.ToString() -match '^10\.70\.3\.' }).Count) {
            throw "Private DNS connectivity required for $hostname. Run this script from an authorized private-network workstation; no firewall or role changes were made."
        }
    }
    & "$PSScriptRoot/Get-ShopAssets.ps1"
    $assets = Get-Content (Join-Path $script:Root 'workload/shop-assets.json') -Raw | ConvertFrom-Json
    $secrets = @(Invoke-Az @('keyvault', 'secret', 'list', '--vault-name', $lab.vaultName))
    foreach ($asset in $assets) {
        $file = Join-Path $script:StateDirectory "shop-assets/$($asset.id).jpg"
        $hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()
        $blob = "shop/$($asset.id).jpg"
        $exists = Invoke-Az @('storage', 'blob', 'exists', '--account-name', $lab.storageName, '--container-name', 'lab', '--name', $blob, '--auth-mode', 'login')
        if ($exists.exists) {
            $existing = Invoke-Az @('storage', 'blob', 'show', '--account-name', $lab.storageName, '--container-name', 'lab', '--name', $blob, '--auth-mode', 'login')
            if ($existing.metadata.PSObject.Properties['srelab_sha256'] -and $existing.metadata.srelab_sha256 -eq $hash) { continue }
            throw "Existing blob $blob differs from the seed asset. Refusing overwrite."
        }
        if ($PSCmdlet.ShouldProcess("$($lab.storageName)/lab/$blob", 'Upload product image with signed-in operator identity')) {
            $null = Invoke-Az @('storage', 'blob', 'upload', '--account-name', $lab.storageName, '--container-name', 'lab', '--name', $blob, '--file', $file, '--auth-mode', 'login', '--overwrite', 'false', '--content-type', 'image/jpeg', '--content-cache-control', 'no-store', '--metadata', "srelab_sha256=$hash", '--no-progress')
        }
    }
    if (-not @($secrets | Where-Object { $_.id -match '/secrets/shop-demo-payment-key$' }).Count -and $PSCmdlet.ShouldProcess($lab.vaultName, 'Create shop-demo-payment-key without displaying its value')) {
        $temporary = [IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($temporary, [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48)), [Text.UTF8Encoding]::new($false))
            $null = Invoke-Az @('keyvault', 'secret', 'set', '--vault-name', $lab.vaultName, '--name', 'shop-demo-payment-key', '--file', $temporary, '--encoding', 'utf-8', '--query', 'id')
        } finally { Remove-Item $temporary -Force }
    }
} finally { $maintenance.Dispose() }