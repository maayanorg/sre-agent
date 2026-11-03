[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([ValidateSet('Plan', 'Restore', 'Verify')][string]$Action = 'Plan')
. "$PSScriptRoot/Common.ps1"
. "$PSScriptRoot/ShopBlobRecovery.ps1"
$lab = Get-Lab -AllowCachedMetadata
$endpointId = "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-blob-swc-001"
$zoneName = 'privatelink.blob.core.windows.net'
if ($Action -eq 'Verify') {
    $storage = Invoke-Az @('storage', 'account', 'show', '-g', $script:ResourceGroup, '-n', $lab.storageName)
    $endpoints = @(Invoke-Az @('network', 'private-endpoint', 'list', '-g', $script:ResourceGroup))
    $endpoint = @($endpoints | Where-Object { $_.id -ieq $endpointId })
    $records = @(Invoke-Az @('network', 'private-dns', 'record-set', 'a', 'list', '-g', $script:ResourceGroup, '-z', $zoneName))
    $record = @($records | Where-Object { $_.name -eq $lab.storageName })
    if ($endpoint.Count -ne 1 -or $endpoint[0].provisioningState -ne 'Succeeded' -or
        $endpoint[0].privateLinkServiceConnections[0].privateLinkServiceConnectionState.status -ne 'Approved' -or
        $endpoint[0].privateLinkServiceConnections[0].privateLinkServiceId -ine $storage.id -or
        $record.Count -ne 1 -or @($record[0].aRecords).Count -ne 1 -or
        @($endpoint[0].customDnsConfigs | Where-Object { $_.ipAddresses -contains $record[0].aRecords[0].ipv4Address }).Count -ne 1) {
        throw 'Blob endpoint, connection approval, or private DNS record is not healthy.'
    }
    & "$PSScriptRoot/Test-PublicShop.ps1"
    return
}

$maintenance = Enter-LabMaintenance
try {
    $group = Invoke-Az @('group', 'show', '-n', $script:ResourceGroup)
    $storage = Invoke-Az @('storage', 'account', 'show', '-g', $script:ResourceGroup, '-n', $lab.storageName)
    $subnet = Invoke-Az @('network', 'vnet', 'subnet', 'show', '-g', $script:ResourceGroup, '--vnet-name', 'vnet-srelab-services-swc-001', '-n', 'snet-private-endpoints')
    $zone = Invoke-Az @('network', 'private-dns', 'zone', 'show', '-g', $script:ResourceGroup, '-n', $zoneName)
    $links = @(Invoke-Az @('network', 'private-dns', 'link', 'vnet', 'list', '-g', $script:ResourceGroup, '-z', $zoneName))
    $endpoints = @(Invoke-Az @('network', 'private-endpoint', 'list', '-g', $script:ResourceGroup))
    $records = @(Invoke-Az @('network', 'private-dns', 'record-set', 'a', 'list', '-g', $script:ResourceGroup, '-z', $zoneName))
    $parameters = New-ShopBlobRecoveryParameters -Lab $lab -Group $group -Subnet $subnet -Storage $storage -Zone $zone -Links $links -Endpoints $endpoints -Records $records
    $file = Join-Path $script:StateDirectory 'shop-blob-recovery.parameters.json'
    Write-LabJson $file $parameters
    $arguments = @('deployment', 'group', 'what-if', '-g', $script:ResourceGroup, '-n', 'srelab-shop-blob-recovery', '--template-file', (Join-Path $script:Root 'infra/endpoints.bicep'), '--parameters', "@$file")
    $preview = Invoke-Az $arguments
    $changes = @($preview.changes | Where-Object { $null -ne $_ })
    $expectedGroupId = "$endpointId/privateDnsZoneGroups/default"
    if ($changes.Count -ne 2 -or @($changes | Where-Object { $_.changeType -ne 'Create' -or ($_.resourceId -ine $endpointId -and $_.resourceId -ine $expectedGroupId) }).Count -ne 0) {
        throw 'What-if must create only the Blob private endpoint and its DNS zone group; refusing deployment.'
    }
    $changes | Select-Object resourceId, changeType
    if ($Action -eq 'Restore' -and $PSCmdlet.ShouldProcess($endpointId, 'Create only missing Blob private endpoint and DNS zone group')) {
        $result = Invoke-Az @('deployment', 'group', 'create', '-g', $script:ResourceGroup, '-n', 'srelab-shop-blob-recovery', '--mode', 'Incremental', '--template-file', (Join-Path $script:Root 'infra/endpoints.bicep'), '--parameters', "@$file")
        if ($result.properties.provisioningState -ne 'Succeeded') { throw 'Blob endpoint recovery deployment did not succeed.' }
        & "$PSScriptRoot/Restore-ShopBlobEndpoint.ps1" -Action Verify
    }
} finally { $maintenance.Dispose() }
