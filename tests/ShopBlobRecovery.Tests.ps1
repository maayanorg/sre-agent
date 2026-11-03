$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/Common.ps1"
. "$PSScriptRoot/../scripts/ShopBlobRecovery.ps1"
$storageId = "$script:GroupId/providers/Microsoft.Storage/storageAccounts/stsrelab2d6ikhr5ewo6o"
$subnetId = "$script:GroupId/providers/Microsoft.Network/virtualNetworks/vnet-srelab-services-swc-001/subnets/snet-private-endpoints"
$zoneId = "$script:GroupId/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
$endpointId = "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-blob-swc-001"
$lab = [pscustomobject]@{ storageName = 'stsrelab2d6ikhr5ewo6o' }
$group = [pscustomobject]@{ id = $script:GroupId; location = $script:Location; tags = [pscustomobject]@{ Project = 'SRE-Day'; Purpose = 'IncidentResponseLab' } }
$storage = [pscustomobject]@{ id = $storageId; name = $lab.storageName; publicNetworkAccess = 'Disabled'; networkRuleSet = [pscustomobject]@{ defaultAction = 'Deny' }; privateEndpointConnections = @() }
$subnet = [pscustomobject]@{ id = $subnetId }
$zone = [pscustomobject]@{ id = $zoneId }
$links = @([pscustomobject]@{ virtualNetwork = [pscustomobject]@{ id = "$script:GroupId/providers/Microsoft.Network/virtualNetworks/vnet-srelab-services-swc-001" }; provisioningState = 'Succeeded' })
$inputs = @{ Lab = $lab; Group = $group; Storage = $storage; Subnet = $subnet; Zone = $zone; Links = $links; Endpoints = @(); Records = @() }
$plan = New-ShopBlobRecoveryParameters @inputs
if ($plan.parameters.targets.value.Count -ne 1 -or $plan.parameters.targets.value[0].id -ne $storageId -or
    $plan.parameters.targets.value[0].zoneId -ne $zoneId -or $plan.parameters.subnetId.value -ne $subnetId) {
    throw 'Recovery must target only the Blob endpoint and its expected subnet and DNS zone.'
}
function Assert-Rejected {
    param($Arguments, [string]$Case)
    try { $null = New-ShopBlobRecoveryParameters @Arguments }
    catch { return }
    throw "Unsafe recovery preflight was accepted: $Case"
}
$invalid = $inputs.Clone()
$invalid.Endpoints = @([pscustomobject]@{ id = $endpointId })
Assert-Rejected $invalid 'existing endpoint'
$invalid = $inputs.Clone()
$invalid.Records = @([pscustomobject]@{ name = $lab.storageName })
Assert-Rejected $invalid 'existing DNS record'
$invalid = $inputs.Clone()
$invalid.Links = @()
Assert-Rejected $invalid 'missing services VNet link'
$storage.publicNetworkAccess = 'Enabled'
Assert-Rejected $inputs 'public storage access enabled'
$storage.publicNetworkAccess = 'Disabled'
$storage.privateEndpointConnections = @([pscustomobject]@{ id = 'other-connection' })
Assert-Rejected $inputs 'unknown storage connection'
$storage.privateEndpointConnections = @()
$subnet.id = "$script:GroupId/providers/Microsoft.Network/virtualNetworks/vnet-srelab-services-swc-001/subnets/snet-client"
Assert-Rejected $inputs 'wrong subnet'
$subnet.id = $subnetId
$lab.storageName = 'unrelated-storage'
Assert-Rejected $inputs 'wrong storage account'
Write-Host 'Shop Blob recovery: scoped parameters and unsafe-state guards passed.'
