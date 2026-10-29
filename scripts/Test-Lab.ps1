[CmdletBinding()]
param([switch]$IncludeTelemetry)
. "$PSScriptRoot/Common.ps1"
$lab = Get-Lab -AllowCachedMetadata
$results = @()
foreach ($target in @('client', 'backend')) {
    $results += Invoke-LabVm -Target $target -Command 'set -e; test -f /opt/srelab/bootstrap-complete; systemctl is-active srelab; mountpoint /mnt/srelab-data; test $(df --output=pcent /mnt/srelab-data | tail -1 | tr -dc 0-9) -lt 95'
}
$results += Invoke-LabVm -Command 'set -e; resolvectl flush-caches; test "$(getent ahostsv4 backend.srelab.internal | head -1 | cut -d" " -f1)" = "10.70.2.4"; for endpoint in health storage vault arm; do echo "Checking $endpoint"; curl -fsS --max-time 25 "http://localhost:8080/$endpoint"; done'
$results += Invoke-LabKube -Command 'kubectl -n srelab rollout status deployment/web --timeout=120s && kubectl -n srelab rollout status deployment/probe --timeout=120s && kubectl -n srelab exec deployment/probe -- curl -fsS --max-time 8 http://web && kubectl -n srelab exec deployment/probe -- curl -fsS --max-time 8 http://backend.srelab.internal:8081/health'
$frontend = (& "$PSScriptRoot/Get-DemoSnapshot.ps1") | ConvertFrom-Json
$expectedChecks = @('web', 'backend', 'client', 'storage', 'vault', 'arm')
if ($frontend.overall -ne 'healthy' -or $frontend.stale -or $frontend.checks.Count -ne 6) { throw 'Frontend does not report six fresh healthy checks.' }
foreach ($checkId in $expectedChecks) {
    $check = @($frontend.checks | Where-Object { $_.id -eq $checkId -and $_.healthy -eq $true })
    if ($check.Count -ne 1) { throw "Frontend check is missing or unhealthy: $checkId" }
}
$results += $frontend | ConvertTo-Json -Depth 8 -Compress
$operatorCommand = (Get-OperatorCheckCommand).Replace("`r`n", "`n")
$encodedOperatorCommand = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($operatorCommand))
$operatorResult = Invoke-LabKube -Command "echo $encodedOperatorCommand | base64 -d | sh"
if ($operatorResult -notmatch 'SRELAB_OPERATOR=healthy') { throw 'Operator service account cannot list pods.' }
$results += 'yes'
if ($results[-1] -notmatch '(?m)^yes\s*$') { throw 'Kubernetes operator role is not healthy.' }
$agent = Invoke-LabRest -Id $lab.agentId -Api '2026-01-01'
if ($agent.properties.provisioningState -ne 'Succeeded') { throw 'SRE Agent is not provisioned successfully.' }
if ($IncludeTelemetry) {
    $query = "Heartbeat | where TimeGenerated > ago(10m) | where Computer in ('client', 'backend') | summarize Computers=dcount(Computer)"
    $telemetry = @(Invoke-Az @('monitor', 'log-analytics', 'query', '-w', $lab.workspaceCustomerId, '--analytics-query', $query))
    if ($telemetry[0].Computers -ne 2) { throw 'Fresh VM heartbeat telemetry is missing.' }
}
Write-LabJson (Join-Path $script:StateDirectory 'baseline-verification.json') @{ timestamp = [DateTime]::UtcNow.ToString('o'); passed = $true; telemetryChecked = [bool]$IncludeTelemetry; evidence = $results }
Write-Host 'Healthy baseline verified: VM services, disk, DNS, six frontend checks, Kubernetes connectivity/RBAC and agent provisioning.'