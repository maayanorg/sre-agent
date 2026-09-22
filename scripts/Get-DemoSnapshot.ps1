[CmdletBinding()]
param([switch]$Page, [switch]$HealthPage)
. "$PSScriptRoot/Common.ps1"
if ($Page -or $HealthPage) {
    $pagePath = if ($HealthPage) { '/health' } else { '/' }
    Invoke-LabKube -Command "kubectl -n srelab exec deployment/probe -- curl -fsS --max-time 15 http://web$pagePath"
    return
}
$command = @'
kubectl -n srelab exec deployment/probe -- sh -c 'payload=$(curl -sS --max-time 15 http://web/api/status 2>/dev/null); result=$?; if [ "$result" -ne 0 ]; then printf "%s\n" "{\"version\":1,\"overall\":\"unavailable\",\"checks\":[]}"; else printf "%s\n" "$payload"; fi'
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($command))
$snapshot = Invoke-LabKube -Command "echo $encoded | base64 -d | sh" | ConvertFrom-Json -Depth 100
if (-not $snapshot.PSObject.Properties['version'] -or $snapshot.version -ne 1) { throw 'Frontend has not produced an observation yet.' }
$snapshot | Add-Member -NotePropertyName transport -NotePropertyValue 'aks-run-command' -Force
$snapshot | Add-Member -NotePropertyName relayReceivedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
if ($snapshot.overall -eq 'unavailable') {
    $snapshot | Add-Member -NotePropertyName observedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
}
$snapshot | ConvertTo-Json -Depth 100 -Compress