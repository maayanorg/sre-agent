$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/ScenarioEngine.ps1"
$script:commands = @()
function Invoke-LabVm {
    param($Target, $Command)
    $script:commands += $Command
    return 'SRELAB_STATE={"active":true,"unitAbsent":true}'
}
function Invoke-LabRest {
    param($Method = 'GET', $Id, $Api, $Body)
    if ($Method -ne 'GET') { throw 'State capture must not mutate Azure.' }
    return @{ value = @(@{ id = "$script:GroupId/providers/Microsoft.Network/networkSecurityGroups/nsg-srelab-workload-swc-001/securityRules/AllowLabHttp"; properties = @{ priority = 100; access = 'Allow'; provisioningState = 'Succeeded' } }) }
}
$service = New-ScenarioState BackendService @{}
if (-not $service.original.active -or $script:commands[-1] -notlike '*{"active":true}*') { throw 'Invalid VM service state marker.' }
$stress = New-ScenarioState CpuPressure @{}
if (-not $stress.original.unitAbsent -or $script:commands[-1] -notlike '*$(systemctl show srelab-incident-cpu.service*') { throw 'Invalid stress preflight shell.' }
$nsg = New-ScenarioState NsgBackend @{}
if ($nsg.injectBody.properties.priority -ne 100 -or $nsg.injectBody.properties.access -ne 'Deny' -or $nsg.original.properties.access -ne 'Allow') { throw 'NSG does not preserve the original rule.' }
if ($nsg.original.properties.ContainsKey('provisioningState')) { throw 'Read-only state in restore body.' }
Write-Host 'Scenario engine: capture is read-only, VM markers valid, NSG priority and original state preserved.'
$timestamp = @{ observedAt = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | ConvertFrom-Json
$age = ([DateTime]::UtcNow - ([DateTime]$timestamp.observedAt).ToUniversalTime()).TotalSeconds
if ($age -lt 0 -or $age -gt 5) { throw 'JSON UTC timestamp lost its timezone.' }
function Invoke-LabRest {
    param($Method = 'GET', $Id, $Api, $Body)
    if ($Method -ne 'GET') { throw 'Endpoint capture must not mutate Azure.' }
    if ($Id.EndsWith('/privateDnsZoneGroups')) {
        return @{ value = @(@{ name = 'default'; properties = @{ privateDnsZoneConfigs = @(@{ name = 'blob'; properties = @{ privateDnsZoneId = 'fixture-zone'; recordSets = @() } }) } }) }
    }
    return @{ name = 'pe-srelab-blob-swc-001'; location = 'swedencentral'; tags = @{ Project = 'SRE-Day' }; properties = @{ subnet = @{ id = 'fixture-subnet' }; networkInterfaces = @(); provisioningState = 'Succeeded'; privateLinkServiceConnections = @(@{ name = 'blob'; id = 'readonly'; properties = @{ groupIds = @('blob'); privateLinkServiceId = 'fixture-storage'; provisioningState = 'Succeeded'; privateLinkServiceConnectionState = @{ status = 'Rejected' } } }); manualPrivateLinkServiceConnections = @() } }
}
$recovery = Get-EndpointRecovery blob
$serialized = $recovery.template | ConvertTo-Json -Depth 30
if ($serialized -match 'Rejected|provisioningState|networkInterfaces|recordSets|readonly') { throw 'Endpoint restore template includes server-managed state.' }
if ($recovery.template.resources.Count -ne 2 -or $recovery.template.resources[1].dependsOn[0] -ne $recovery.endpointId) { throw 'Endpoint DNS recovery dependency is missing.' }
Write-Host 'Endpoint recovery captures configuration and DNS bindings without rejected connection state.'