[CmdletBinding(SupportsShouldProcess)]
param([switch]$CleanupOnly)
. "$PSScriptRoot/Common.ps1"
$lab = Get-Lab
$maintenance = Enter-LabMaintenance
$statePath = Join-Path $script:StateDirectory 'shop-seed-grants.json'
$grants = @()
$scopes = @(
    @{ scope = "$script:GroupId/providers/Microsoft.Storage/storageAccounts/$($lab.storageName)/blobServices/default/containers/lab"; role = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' },
    @{ scope = "$script:GroupId/providers/Microsoft.KeyVault/vaults/$($lab.vaultName)"; role = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' }
)
function Remove-SeedGrants {
    foreach ($grant in $grants) {
        $expected = @($scopes | Where-Object { $_.scope -eq $grant.scope -and $_.role -eq $grant.role })
        if ($expected.Count -ne 1 -or $grant.id -notmatch ('^' + [regex]::Escape($grant.scope) + '/providers/Microsoft.Authorization/roleAssignments/[0-9a-f-]{36}$')) { throw 'Invalid seed recovery record; refusing role deletion.' }
        $existing = @(Invoke-Az @('role', 'assignment', 'list', '--scope', $grant.scope) | Where-Object { $_.id -eq $grant.id })
        if ($existing.Count) {
            if ($existing[0].principalId -ne $lab.appPrincipalId -or -not $existing[0].roleDefinitionId.EndsWith($grant.role)) { throw 'Seed assignment identity mismatch.' }
            $null = Invoke-Az @('role', 'assignment', 'delete', '--ids', $grant.id)
        }
        $remaining = @(Invoke-Az @('role', 'assignment', 'list', '--scope', $grant.scope) | Where-Object { $_.id -eq $grant.id })
        if ($remaining.Count) { throw 'Temporary seed role is still assigned.' }
    }
    if (Test-Path $statePath) { Remove-Item $statePath }
    Write-Host 'Temporary seed role assignments removed and absence verified.'
}
try {
    if ($CleanupOnly) {
        if (-not (Test-Path $statePath)) { Write-Host 'No seed grants recorded.'; return }
        $grants = @((Get-Content $statePath -Raw | ConvertFrom-Json).grants)
        if ($PSCmdlet.ShouldProcess($script:ResourceGroup, 'Remove recorded temporary shop seed grants')) { Remove-SeedGrants }
        return
    }
    if (Test-Path $statePath) { throw 'Seed grant recovery record exists. Run -CleanupOnly before retrying.' }
    if (-not $PSCmdlet.ShouldProcess($script:ResourceGroup, 'Temporarily grant Blob container Contributor and Vault Secrets Officer, seed on client VM, then remove grants')) { return }
    try {
        foreach ($scope in $scopes) {
            $existing = @(Invoke-Az @('role', 'assignment', 'list', '--scope', $scope.scope) | Where-Object { $_.principalId -eq $lab.appPrincipalId -and $_.roleDefinitionId.EndsWith($scope.role) })
            if ($existing.Count) { throw 'A write role already exists. Resolve it before seeding so fault tests retain read-only runtime access.' }
            $name = [guid]::NewGuid().ToString()
            $grants += @{ id = "$($scope.scope)/providers/Microsoft.Authorization/roleAssignments/$name"; scope = $scope.scope; role = $scope.role }
            Write-LabJson $statePath @{ grants = $grants }
            $null = Invoke-Az @('role', 'assignment', 'create', '--name', $name, '--assignee-object-id', $lab.appPrincipalId, '--assignee-principal-type', 'ServicePrincipal', '--role', $scope.role, '--scope', $scope.scope)
        }
        $source = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:Root 'scripts/seed-shop.cjs')))
        $assets = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:Root 'workload/shop-assets.json')))
        $command = @'
set -e
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
echo '__SOURCE__' | base64 -d > "$temporary/seed.cjs"
echo '__ASSETS__' | base64 -d > "$temporary/assets.json"
node "$temporary/seed.cjs" "$temporary/assets.json"
'@
        Invoke-LabVm -Target client -Command $command.Replace('__SOURCE__', $source).Replace('__ASSETS__', $assets)
    } finally { if ($grants.Count) { Remove-SeedGrants } }
} finally { $maintenance.Dispose() }