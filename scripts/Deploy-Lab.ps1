[CmdletBinding()]
param([switch]$ValidateOnly, [string]$VmSize = 'Standard_B1ms', [string]$AksVmSize = 'Standard_D2s_v4')
. "$PSScriptRoot/Common.ps1"
$maintenance = Enter-LabMaintenance
try {
$account = Invoke-Az @('account', 'show')
if ($account.id -ne $script:Subscription -or $account.state -ne 'Enabled') { throw 'Wrong or disabled subscription.' }
$exists = Invoke-Az @('group', 'exists', '-n', $script:ResourceGroup)
if ($exists) { Assert-Lab } else {
    $null = Invoke-Az (@('group', 'create', '-n', $script:ResourceGroup, '-l', $script:Location, '--tags') + $script:Tags)
}
$access = Invoke-Az @('account', 'get-access-token', '--resource', 'https://management.azure.com/')
$payload = $access.accessToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
$payload = $payload.PadRight($payload.Length + (4 - $payload.Length % 4) % 4, '=')
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
if ($claims.tid -ne $account.tenantId) { throw 'Operator token is from the wrong tenant.' }
$operatorId = $claims.oid
Remove-Variable access, payload, claims
$sshDirectory = Join-Path $HOME '.ssh'
$null = New-Item -ItemType Directory -Path $sshDirectory -Force
$keyPath = Join-Path $sshDirectory 'srelab_ed25519'
if (-not (Test-Path "$keyPath.pub")) {
    & ssh-keygen -q -t ed25519 -N '' -C 'srelab-event' -f $keyPath
    if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' }
}
$parameterPath = Join-Path $script:StateDirectory 'parameters.json'
Write-LabJson $parameterPath @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
        sshPublicKey = @{ value = (Get-Content "$keyPath.pub" -Raw).Trim() }
        operatorObjectId = @{ value = $operatorId }
        vmSize = @{ value = $VmSize }
        aksVmSize = @{ value = $AksVmSize }
    }
}
$template = Join-Path $script:Root 'infra/main.bicep'
$arguments = @('deployment', 'group', 'validate', '-g', $script:ResourceGroup, '-n', 'srelab-baseline', '--template-file', $template, '--parameters', "@$parameterPath")
$null = Invoke-Az $arguments
Write-Host 'Azure template validation passed.'
if ($ValidateOnly) { return }
$null = Invoke-Az @('deployment', 'group', 'what-if', '-g', $script:ResourceGroup, '--template-file', $template, '--parameters', "@$parameterPath", '--no-pretty-print')
$result = Invoke-Az @('deployment', 'group', 'create', '-g', $script:ResourceGroup, '-n', 'srelab-baseline', '--template-file', $template, '--parameters', "@$parameterPath")
Write-LabJson (Join-Path $script:StateDirectory 'lab.json') $result.properties.outputs.lab.value
$null = Invoke-Az (@('group', 'update', '-n', $script:NodeResourceGroup, '--tags') + $script:Tags)
Write-Host 'Infrastructure deployed. Initialize workloads and validate the healthy baseline next.'
} finally { $maintenance.Dispose() }