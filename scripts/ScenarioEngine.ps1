. "$PSScriptRoot/Common.ps1"
. "$PSScriptRoot/ScenarioCatalog.ps1"

function ConvertTo-LabMap {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100)
}

function Get-ArmChild {
    param([string]$Id, [string]$Api)
    $parent = $Id.Substring(0, $Id.LastIndexOf('/'))
    $items = Invoke-LabRest -Id $parent -Api $Api
    return @($items.value | Where-Object { $_.id -ieq $Id })
}

function Get-RestorableBody {
    param($Resource)
    $source = ConvertTo-LabMap $Resource
    $body = @{ properties = $source.properties }
    foreach ($key in @('location', 'tags')) { if ($source.ContainsKey($key)) { $body[$key] = $source[$key] } }
    foreach ($key in @('provisioningState', 'virtualNetworkLinkState', 'fqdn', 'isAutoRegistered', 'scope', 'createdOn', 'updatedOn', 'createdBy', 'updatedBy')) { $body.properties.Remove($key) }
    return $body
}

function Get-EndpointRecovery {
    param([ValidateSet('blob', 'vault')][string]$Target)
    $endpointId = "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-$Target-swc-001"
    $endpoint = ConvertTo-LabMap (Invoke-LabRest -Id $endpointId)
    $groups = Invoke-LabRest -Id "$endpointId/privateDnsZoneGroups"
    $properties = $endpoint.properties
    foreach ($key in @('provisioningState', 'resourceGuid', 'networkInterfaces', 'customDnsConfigs')) { $properties.Remove($key) }
    foreach ($kind in @('privateLinkServiceConnections', 'manualPrivateLinkServiceConnections')) {
        foreach ($connection in $properties[$kind]) {
            foreach ($key in @('id', 'etag', 'type')) { $connection.Remove($key) }
            foreach ($key in @('provisioningState', 'privateLinkServiceConnectionState')) { $connection.properties.Remove($key) }
        }
    }
    $resources = @(@{ type = 'Microsoft.Network/privateEndpoints'; apiVersion = '2024-05-01'; name = $endpoint.name; location = $endpoint.location; tags = $endpoint.tags; properties = $properties })
    foreach ($group in $groups.value) {
        $configs = @($group.properties.privateDnsZoneConfigs | ForEach-Object { @{ name = $_.name; properties = @{ privateDnsZoneId = $_.properties.privateDnsZoneId } } })
        $resources += @{ type = 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups'; apiVersion = '2024-05-01'; name = "$($endpoint.name)/$($group.name)"; dependsOn = @($endpointId); properties = @{ privateDnsZoneConfigs = $configs } }
    }
    return @{ endpointId = $endpointId; template = @{ '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'; contentVersion = '1.0.0.0'; resources = $resources } }
}

function Invoke-ScenarioShell {
    param([string]$Command)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Command.Replace("`r`n", "`n")))
    Invoke-LabKube -Command "echo $encoded | base64 -d | sh"
}

function Invoke-ScenarioManifest {
    param($Manifest)
    $file = Join-Path $script:StateDirectory 'incident-manifest.json'
    Write-LabJson $file $Manifest
    Invoke-LabKube -File $file -Command 'kubectl apply -f incident-manifest.json'
}

function Get-ScenarioVmState {
    param([string]$Target, [string]$Command)
    $output = Invoke-LabVm -Target $Target -Command "set -e; $Command"
    $match = [regex]::Match($output, '(?m)^SRELAB_STATE=(.+)\r?$')
    if (-not $match.Success) { throw 'VM did not return a state marker.' }
    return ($match.Groups[1].Value | ConvertFrom-Json -AsHashtable)
}

function New-ScenarioState {
    param([string]$Scenario, $Lab)
    $definition = Get-ScenarioDefinition $Scenario
    $state = @{ version = 1; scenario = $Scenario; groupId = $script:GroupId; phase = 'Prepared'; timestamp = [DateTime]::UtcNow.ToString('o'); kind = $definition.kind; check = $definition.check }
    switch ($definition.kind) {
        { $_ -in @('ArmDelete', 'ArmUpdate', 'ArmCreate', 'Role', 'Endpoint') } {
            $state.api = if ($definition['api']) { $definition.api } else { '2022-04-01' }
            $state.id = if ($definition['path']) { "$script:GroupId$($definition.path)" } else { '' }
            if ($definition.kind -eq 'Role') { $state.id = $Lab.($definition.assignment) }
            if ($definition.kind -eq 'Endpoint') {
                $state.api = if ($definition.target -eq 'blob') { '2023-05-01' } else { '2023-07-01' }
                $parent = if ($definition.target -eq 'blob') { "$script:GroupId/providers/Microsoft.Storage/storageAccounts/$($Lab.storageName)" } else { "$script:GroupId/providers/Microsoft.KeyVault/vaults/$($Lab.vaultName)" }
                $connections = Invoke-LabRest -Id "$parent/privateEndpointConnections" -Api $state.api
                $connection = @($connections.value | Where-Object { $_.properties.privateEndpoint.id -ieq "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-$($definition.target)-swc-001" })
                if ($connection.Count -ne 1) { throw 'Expected exactly one lab private endpoint connection.' }
                $state.id = $connection[0].id
            }
            $existing = @(Get-ArmChild -Id $state.id -Api $state.api)
            if ($definition.kind -eq 'ArmCreate') {
                if ($existing.Count) { throw 'Reserved incident resource already exists; refusing overwrite.' }
                if ($Scenario -like 'Route*') {
                    $state.injectBody = @{ properties = @{ addressPrefix = '10.70.2.4/32'; nextHopType = 'None' } }
                    if ($Scenario -eq 'RouteWrongHop') { $state.injectBody.properties.nextHopType = 'VirtualAppliance'; $state.injectBody.properties.nextHopIpAddress = '10.70.1.250' }
                }
                $state.original = $null
            } else {
                if ($existing.Count -ne 1) { throw 'Baseline resource missing; refusing injection.' }
                $state.original = Get-RestorableBody $existing[0]
                if ($definition.kind -eq 'Role' -and $state.original.properties.principalId -ne $Lab.appPrincipalId) { throw 'Role does not belong to the lab workload identity.' }
                if ($definition.kind -eq 'Endpoint') {
                    $connectionState = ConvertTo-LabMap $existing[0].properties.privateLinkServiceConnectionState
                    if ($connectionState.status -ne 'Approved') { throw 'Endpoint must be Approved before injection.' }
                    $state.original = @{ properties = @{ privateLinkServiceConnectionState = $connectionState } }
                    $state.endpointRecovery = Get-EndpointRecovery -Target $definition.target
                }
                if ($Scenario -eq 'DnsRecordWrong') {
                    $state.injectBody = ConvertTo-LabMap $state.original
                    $state.injectBody.properties.aRecords = @(@{ ipv4Address = '10.70.2.250' })
                }
                if ($Scenario -eq 'NsgBackend') {
                    $state.injectBody = @{ properties = @{ priority = $state.original.properties.priority; protocol = 'Tcp'; access = 'Deny'; direction = 'Inbound'; sourcePortRange = '*'; destinationPortRange = '8081'; sourceAddressPrefix = 'VirtualNetwork'; destinationAddressPrefix = '10.70.2.4' } }
                }
            }
        }
        { $_ -in @('KubeDeployment', 'KubeRole') } {
            $resource = if ($definition.kind -eq 'KubeRole') { 'rolebinding operator-reader' } else { 'deployment web' }
            $original = Invoke-LabKube -Command "kubectl -n srelab get $resource -o json" | ConvertFrom-Json -AsHashtable -Depth 100
            $state.uid = $original.metadata.uid
            $state.original = @{ apiVersion = $original.apiVersion; kind = $original.kind; metadata = @{ name = $original.metadata.name; namespace = 'srelab' } }
            if ($definition.kind -eq 'KubeRole') {
                $state.original.roleRef = $original.roleRef; $state.original.subjects = $original.subjects
            } else {
                if ($original.spec.replicas -lt 1 -or $original.status['availableReplicas'] -lt 1) { throw 'Web must be available before injection.' }
                $state.original.spec = $original.spec
                $state.injectBody = ConvertTo-LabMap $state.original
                $state.injectBody.spec.strategy = @{ type = 'Recreate' }
                $container = $state.injectBody.spec.template.spec.containers[0]
                switch ($Scenario) {
                    'AksBadImage' { $container.image = 'node:srelab-intentionally-missing-image' }
                    'AksCrashLoop' { $container.command = @('node', '-e', 'process.exit(42)') }
                    'AksReadiness' { $container.readinessProbe.httpGet.path = '/srelab-missing-readiness' }
                    'AksScheduling' { $state.injectBody.spec.template.spec.nodeSelector = @{ 'srelab/nonexistent' = 'incident' } }
                    'AksOom' { $container.command = @('node', '-e', 'const blocks=[];setInterval(()=>blocks.push(Buffer.alloc(16*1024*1024,1)),100)') }
                }
            }
        }
        'VmPower' {
            $state.target = $definition.target
            $view = Invoke-Az @('vm', 'get-instance-view', '-g', $script:ResourceGroup, '-n', "vm-srelab-$($state.target)-swc-001")
            if (-not @($view.instanceView.statuses | Where-Object code -eq 'PowerState/running').Count) { throw 'VM must be running before injection.' }
            $state.original = 'running'
        }
        'VmService' {
            $state.target = $definition.target; $state.service = $definition.service
            $state.original = Get-ScenarioVmState $state.target ('systemctl is-active --quiet {0}; test ! -e /run/systemd/system/{0}.service.d/90-srelab-incident.conf; test ! -L /run/systemd/system/{0}.service.d/90-srelab-incident.conf; echo ''SRELAB_STATE={{"active":true}}''' -f $state.service)
        }
        'VmFile' {
            $state.target = $definition.target
            if ($Scenario -eq 'BadConfig') {
                $state.original = Get-ScenarioVmState $state.target 'test ! -L /opt/srelab/config.json; printf ''SRELAB_STATE={"content":"%s"}\n'' "$(base64 -w0 /opt/srelab/config.json)"'
            } else {
                $state.original = Get-ScenarioVmState $state.target 'mountpoint -q /mnt/srelab-data; test ! -e /mnt/srelab-data/srelab-incident.fill; test $(df -B1 --output=size /mnt/srelab-data | tail -1) -le 134217728; printf ''SRELAB_STATE={"reservedFileAbsent":true}\n'''
            }
        }
        'VmStress' {
            $state.target = $definition.target
            $state.unit = if ($Scenario -eq 'CpuPressure') { 'srelab-incident-cpu' } else { 'srelab-incident-memory' }
            $state.original = Get-ScenarioVmState $state.target ('command -v stress-ng >/dev/null; test "$(systemctl show {0}.service -p LoadState --value)" = not-found; echo ''SRELAB_STATE={{"unitAbsent":true}}''' -f $state.unit)
        }
    }
    return $state
}

function Set-ScenarioMutation {
    param($State, [switch]$Restore)
    $definition = Get-ScenarioDefinition $State.scenario
    if ($State.kind -eq 'Endpoint') {
        $endpointId = $State.endpointRecovery.endpointId
        $expectedId = "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-$($definition.target)-swc-001"
        if ($endpointId -ine $expectedId) { throw 'Endpoint recovery scope mismatch.' }
        if (-not $Restore -or $State.endpointRecovery['replaceRejected']) {
            $null = Invoke-Az @('network', 'private-endpoint', 'delete', '--ids', $endpointId)
        }
        if ($Restore) {
            $file = Join-Path $script:StateDirectory 'endpoint-restore.json'
            Write-LabJson $file $State.endpointRecovery.template
            $deployment = Invoke-Az @('deployment', 'group', 'create', '-g', $script:ResourceGroup, '-n', 'srelab-endpoint-recovery', '--mode', 'Incremental', '--template-file', $file)
            if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Endpoint recovery deployment did not succeed.' }
        }
        return
    }
    switch ($State.kind) {
        { $_ -in @('ArmDelete', 'ArmUpdate', 'ArmCreate', 'Role', 'Endpoint') } {
            $delete = if ($Restore) { $State.kind -eq 'ArmCreate' } else { $State.kind -in @('ArmDelete', 'Role') }
            if ($delete) {
                if (@(Get-ArmChild $State.id $State.api).Count) { $null = Invoke-LabRest -Method DELETE -Id $State.id -Api $State.api }
            } else {
                $body = if ($Restore) { $State.original } else { $State.injectBody }
                $null = Invoke-LabRest -Method PUT -Id $State.id -Api $State.api -Body $body
            }
        }
        'KubeDeployment' {
            $current = Invoke-LabKube -Command 'kubectl -n srelab get deployment web -o json' | ConvertFrom-Json
            if ($current.metadata.uid -ne $State.uid) { throw 'Deployment UID changed; refusing mutation.' }
            $manifest = if ($Restore) { $State.original } else { $State.injectBody }
            $patchFile = Join-Path $script:StateDirectory 'incident-patch.json'
            Write-LabJson $patchFile @(@{ op = 'replace'; path = '/spec'; value = $manifest.spec })
            Invoke-LabKube -File $patchFile -Command 'kubectl -n srelab patch deployment web --type=json --patch-file=incident-patch.json'
            if ($Restore) { Invoke-LabKube -Command 'kubectl -n srelab rollout status deployment/web --timeout=240s' }
        }
        'KubeRole' {
            $current = Invoke-LabKube -Command 'kubectl -n srelab get rolebinding operator-reader -o json' | ConvertFrom-Json
            if ($current.metadata.uid -ne $State.uid) { throw 'RoleBinding UID changed; refusing mutation.' }
            $subjects = if ($Restore) { @($State.original.subjects) } else { @() }
            $patchFile = Join-Path $script:StateDirectory 'incident-patch.json'
            Write-LabJson $patchFile @{ subjects = @($subjects) }
            Invoke-LabKube -File $patchFile -Command 'kubectl -n srelab patch rolebinding operator-reader --type=merge --patch-file=incident-patch.json'
        }
        'VmPower' {
            $operation = if ($Restore) { 'start' } else { 'deallocate' }
            $null = Invoke-Az @('vm', $operation, '-g', $script:ResourceGroup, '-n', "vm-srelab-$($State.target)-swc-001")
        }
        'VmService' {
            $override = "/run/systemd/system/$($State.service).service.d/90-srelab-incident.conf"
            if ($Restore) {
                Invoke-LabVm -Target $State.target -Command "set -e; rm -f -- $override; systemctl daemon-reload; systemctl start $($State.service); systemctl is-active --quiet $($State.service)"
            } else {
                Invoke-LabVm -Target $State.target -Command "set -e; test ! -e $override; test ! -L $override; mkdir -p /run/systemd/system/$($State.service).service.d; printf '[Service]\nExecCondition=/bin/false\n' > $override; systemctl daemon-reload; systemctl stop $($State.service); if systemctl is-active --quiet $($State.service); then exit 1; fi"
            }
        }
        'VmFile' {
            if ($State.scenario -eq 'BadConfig') {
                $content = $State.original.content
                if (-not $Restore) {
                    $config = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content)) | ConvertFrom-Json -AsHashtable
                    $config.release = 'srelab-invalid-release'
                    $content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($config | ConvertTo-Json -Compress)))
                }
                Invoke-LabVm -Target $State.target -Command "set -e; test ! -L /opt/srelab/config.json; echo '$content' | base64 -d > /opt/srelab/config.json"
            } elseif ($Restore) {
                Invoke-LabVm -Target $State.target -Command 'set -e; mountpoint -q /mnt/srelab-data; rm -f -- /mnt/srelab-data/srelab-incident.fill'
            } else {
                Invoke-LabVm -Target $State.target -Command 'set -e; mountpoint -q /mnt/srelab-data; test ! -e /mnt/srelab-data/srelab-incident.fill; available=$(df -B1 --output=avail /mnt/srelab-data | tail -1); test "$available" -gt 0; fallocate -l "$available" /mnt/srelab-data/srelab-incident.fill'
            }
        }
        'VmStress' {
            if ($Restore) {
                Invoke-LabVm -Target $State.target -Command "systemctl stop $($State.unit).service 2>/dev/null || true; systemctl reset-failed $($State.unit).service 2>/dev/null || true"
            } else {
                $stress = if ($State.scenario -eq 'CpuPressure') { '--cpu 1 --cpu-load 90' } else { '--vm 1 --vm-bytes 256M --vm-keep' }
                Invoke-LabVm -Target $State.target -Command "set -e; systemd-run --unit=$($State.unit) --collect -p RuntimeMaxSec=600 -p MemoryMax=384M -p CPUQuota=90% /usr/bin/stress-ng $stress --timeout 580s"
            }
        }
    }
}