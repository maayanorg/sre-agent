function New-ShopBlobRecoveryParameters {
    param($Lab, $Group, $Subnet, $Storage, $Zone, $Links, $Endpoints, $Records)
    $endpointId = "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-blob-swc-001"
    $storageId = "$script:GroupId/providers/Microsoft.Storage/storageAccounts/stsrelab2d6ikhr5ewo6o"
    $subnetId = "$script:GroupId/providers/Microsoft.Network/virtualNetworks/vnet-srelab-services-swc-001/subnets/snet-private-endpoints"
    $zoneId = "$script:GroupId/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    $servicesVnetId = "$script:GroupId/providers/Microsoft.Network/virtualNetworks/vnet-srelab-services-swc-001"
    if ($Lab.storageName -ne 'stsrelab2d6ikhr5ewo6o') { throw 'Lab metadata does not identify the expected shop storage account.' }
    if ($Group.id -ine $script:GroupId -or $Group.location -ne $script:Location -or
        $Group.tags.Project -ne 'SRE-Day' -or $Group.tags.Purpose -ne 'IncidentResponseLab') {
        throw 'Resource group is not the expected lab scope.'
    }
    if ($Storage.id -ine $storageId -or $Storage.publicNetworkAccess -ne 'Disabled' -or
        $Storage.networkRuleSet.defaultAction -ne 'Deny' -or $Subnet.id -ine $subnetId -or $Zone.id -ine $zoneId) {
        throw 'Storage, subnet, or private DNS zone differs from the protected lab baseline.'
    }
    if (@($Endpoints | Where-Object { $_.id -ieq $endpointId }).Count -ne 0) {
        throw 'Blob private endpoint already exists; do not overwrite it. Inspect its connection and DNS state.'
    }
    if (@($Storage.privateEndpointConnections | Where-Object { $null -ne $_ }).Count -ne 0) {
        throw 'Storage has private endpoint connections; inspect them before changing the network.'
    }
    if (@($Records | Where-Object { $_.name -eq $Storage.name }).Count -ne 0) {
        throw 'Blob private DNS A record already exists; do not overwrite it.'
    }
    if (@($Links | Where-Object { $_.virtualNetwork.id -ieq $servicesVnetId -and $_.provisioningState -eq 'Succeeded' }).Count -ne 1) {
        throw 'Blob private DNS zone is not linked to the services VNet.'
    }
    return @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = @{
            location = @{ value = $script:Location }
            tags = @{ value = $Group.tags }
            subnetId = @{ value = $subnetId }
            targets = @{ value = @(@{ name = 'blob'; id = $storageId; groupId = 'blob'; zoneId = $zoneId }) }
        }
    }
}
