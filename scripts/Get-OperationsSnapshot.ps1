[CmdletBinding()]
param([switch]$AllowCachedMetadata)
. "$PSScriptRoot/ScenarioEngine.ps1"
$lab = Get-Lab -AllowCachedMetadata:$AllowCachedMetadata
$checks = [Collections.Generic.List[object]]::new()
function Add-Observation {
    param([string]$Id, [string]$State, [string]$Detail)
    $checks.Add(@{ id = $Id; state = $State; detail = $Detail; observedAt = [DateTime]::UtcNow.ToString('o') })
}
try {
    $command = "set -e`nkubectl -n srelab get deployment web -o json`n" + (Get-OperatorCheckCommand)
    $output = Invoke-ScenarioShell $command
    $marker = [regex]::Match($output, 'SRELAB_OPERATOR=(healthy|failed|unknown)')
    if (-not $marker.Success) { throw 'Operator evidence missing.' }
    $deployment = $output.Substring(0, $marker.Index).Trim() | ConvertFrom-Json -AsHashtable -Depth 100
    $available = [int]$deployment.status['availableReplicas']
    $desired = [int]$deployment.spec.replicas
    $ready = $desired -gt 0 -and $available -ge $desired -and [int]$deployment.status['updatedReplicas'] -eq $desired -and [long]$deployment.status['observedGeneration'] -ge [long]$deployment.metadata.generation
    Add-Observation 'aks' $(if ($ready) { 'healthy' } else { 'failed' }) "Web deployment: $available available / $desired desired; $($deployment.status['updatedReplicas']) updated"
    $operator = $marker.Groups[1].Value
    Add-Observation 'operator' $operator $(if ($operator -eq 'healthy') { 'Operator token can list namespace pods' } elseif ($operator -eq 'failed') { 'Authorization denied: operator cannot list namespace pods' } else { 'Operator authorization could not be established' })
} catch {
    Add-Observation 'aks' 'unknown' 'Kubernetes observation unavailable'
    Add-Observation 'operator' 'unknown' 'Operator authorization observation unavailable'
}
$backendRunning = $false
foreach ($target in @('client', 'backend')) {
    try {
        $view = Invoke-Az @('vm', 'get-instance-view', '-g', $script:ResourceGroup, '-n', "vm-srelab-$target-swc-001")
        $power = @($view.instanceView.statuses | Where-Object { $_.code -like 'PowerState/*' })
        if ($power.Count -ne 1) { throw 'Power state missing.' }
        $running = $power[0].code -eq 'PowerState/running'
        Add-Observation "$target-vm" $(if ($running) { 'healthy' } else { 'failed' }) $power[0].displayStatus
        if ($target -eq 'backend') { $backendRunning = $running }
    } catch { Add-Observation "$target-vm" 'unknown' 'VM power observation unavailable' }
}
if ($backendRunning) {
    try {
        $command = @'
cpu=$(vmstat 1 2 | tail -1 | awk '{print 100-$15}')
memory=$(awk '/MemTotal:/ {total=$2} /MemAvailable:/ {available=$2} END {printf "%.0f",100*(total-available)/total}' /proc/meminfo)
stress=$(systemctl show srelab-incident-memory.service -p MemoryCurrent --value 2>/dev/null || true)
case "$stress" in ''|*[!0-9]*) stress=0;; esac
disk=$(df --output=pcent /mnt/srelab-data | tail -1 | tr -dc '0-9')
ama=false
if systemctl is-active --quiet azuremonitoragent; then ama=true; fi
printf 'SRELAB_STATE={"cpu":%s,"memory":%s,"stressBytes":%s,"disk":%s,"ama":%s}\n' "$cpu" "$memory" "$stress" "$disk" "$ama"
'@
        $resources = Get-ScenarioVmState 'backend' $command
        Add-Observation 'cpu' $(if ($resources.cpu -ge 75) { 'failed' } else { 'healthy' }) "Backend CPU busy: $($resources.cpu)% (threshold 75%)"
        $memoryPressure = $resources.memory -ge 85 -or $resources.stressBytes -ge 134217728
        Add-Observation 'memory' $(if ($memoryPressure) { 'failed' } else { 'healthy' }) "Backend memory used: $($resources.memory)%; stress working set: $([Math]::Round($resources.stressBytes / 1MB)) MiB (thresholds 85% / 128 MiB)"
        Add-Observation 'disk' $(if ($resources.disk -ge 95) { 'failed' } else { 'healthy' }) "Backend lab data filesystem: $($resources.disk)% used (threshold 95%)"
        Add-Observation 'ama' $(if ($resources.ama) { 'healthy' } else { 'failed' }) $(if ($resources.ama) { 'Backend Azure Monitor Agent service active' } else { 'Backend Azure Monitor Agent service inactive; telemetry delivery interrupted' })
    } catch { foreach ($id in @('cpu', 'memory', 'disk', 'ama')) { Add-Observation $id 'unknown' 'Backend resource observation unavailable' } }
} else { foreach ($id in @('cpu', 'memory', 'disk', 'ama')) { Add-Observation $id 'unknown' 'Backend is not confirmed running' } }
try {
    $query = "let expected=datatable(Computer:string)['client','backend']; expected | join kind=leftouter (Heartbeat | where TimeGenerated > ago(24h) | where Computer in ('client','backend') | summarize LastSeen=max(TimeGenerated) by Computer) on Computer | project Computer, LastSeen, AgeSeconds=datetime_diff('second',now(),LastSeen)"
    $heartbeats = @(Invoke-Az @('monitor', 'log-analytics', 'query', '-w', $lab.workspaceCustomerId, '--analytics-query', $query))
    foreach ($hostName in @('client', 'backend')) {
        $row = @($heartbeats | Where-Object Computer -eq $hostName)
        if ($row.Count -ne 1) { throw 'Expected-host heartbeat query returned an unexpected shape.' }
        $fresh = $row[0].LastSeen -and [double]$row[0].AgeSeconds -le 600
        Add-Observation "$hostName-heartbeat" $(if ($fresh) { 'healthy' } else { 'failed' }) $(if ($row[0].LastSeen) { "Latest heartbeat: $($row[0].LastSeen) UTC; freshness limit 10 minutes" } else { 'No heartbeat in the last 24 hours for this expected VM' })
    }
} catch { foreach ($hostName in @('client', 'backend')) { Add-Observation "$hostName-heartbeat" 'unknown' 'Log Analytics heartbeat query unavailable' } }
@{ version = 1; observedAt = [DateTime]::UtcNow.ToString('o'); checks = @($checks.ToArray()); transport = 'azure-operator-relay' } | ConvertTo-Json -Depth 10 -Compress