[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Inject', 'Reset', 'Status')][string]$Action = 'Status')
. "$PSScriptRoot/Common.ps1"
Assert-Lab
$null = New-Item -ItemType Directory -Path $script:StateDirectory -Force
$statePath = Join-Path $script:StateDirectory 'web-outage.json'
$lock = [IO.File]::Open((Join-Path $script:StateDirectory 'incident.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $deployment = Invoke-LabKube -Command 'kubectl -n srelab get deployment web -o json' | ConvertFrom-Json -Depth 100
    if ($Action -eq 'Status') {
        Invoke-LabKube -Command 'kubectl -n srelab get deployment web; kubectl -n srelab get pods -l app=srelab-web'
        Write-Host "Saved recovery state: $(Test-Path $statePath)"
        return
    }
    if ($Action -eq 'Inject') {
        if (Test-Path $statePath) { throw 'An outage is already recorded. Use Reset before another injection.' }
        if (Test-Path (Join-Path $script:StateDirectory 'active-incident.json')) { throw 'Another lab incident is active.' }
        if ($deployment.spec.replicas -lt 1 -or $deployment.status.availableReplicas -lt 1) { throw 'Web must be serving before injection.' }
        if (-not $PSCmdlet.ShouldProcess('srelab/deployment/web', 'Save replica count and scale to zero')) { return }
        Write-LabJson $statePath @{ uid = $deployment.metadata.uid; replicas = [int]$deployment.spec.replicas; timestamp = [DateTime]::UtcNow.ToString('o') }
        Invoke-LabKube -Command 'kubectl -n srelab scale deployment/web --replicas=0 && kubectl -n srelab wait --for=delete pod -l app=srelab-web --timeout=120s'
        Write-Host 'Web is stopped. Keep the viewer open to see the failed request. Restore with -Action Reset.'
    } else {
        if (-not (Test-Path $statePath)) { throw 'No saved web outage state. Nothing was changed.' }
        $state = Get-Content $statePath -Raw | ConvertFrom-Json
        if ($state.uid -ne $deployment.metadata.uid) { throw 'Deployment UID changed; refusing to restore a different deployment.' }
        $replicas = [int]$state.replicas
        if ($replicas -lt 1 -or $replicas -gt 10) { throw 'Invalid saved replica count.' }
        if (-not $PSCmdlet.ShouldProcess('srelab/deployment/web', "Restore $replicas replicas")) { return }
        Invoke-LabKube -Command "kubectl -n srelab scale deployment/web --replicas=$replicas && kubectl -n srelab rollout status deployment/web --timeout=240s"
        Invoke-LabKube -Command 'kubectl -n srelab exec deployment/probe -- curl -fsS --max-time 15 http://web/healthz'
        Remove-Item $statePath
        Write-Host 'Web restored and reachable. Dependency observations may need one collection cycle to refresh.'
    }
} finally { $lock.Dispose() }