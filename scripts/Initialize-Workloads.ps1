[CmdletBinding()]
param()
. "$PSScriptRoot/Common.ps1"
$maintenance = Enter-LabMaintenance
try {
$lab = Get-Lab
$webResources = (& "$PSScriptRoot/Get-FrontendManifest.ps1").items
if (Test-Path (Join-Path $script:StateDirectory 'web-outage.json')) { throw 'Restore the active web outage before initializing workloads.' }
foreach ($target in @('client', 'backend')) {
    Invoke-LabVm -Target $target -Command 'set -e; cloud-init status --wait; test -f /opt/srelab/bootstrap-complete; systemctl is-active srelab; mountpoint /mnt/srelab-data'
}
$manifest = @{
    apiVersion = 'v1'; kind = 'List'; items = @(
        @{ apiVersion = 'v1'; kind = 'Namespace'; metadata = @{ name = 'srelab'; labels = @{ purpose = 'srelab' } } },
        @{ apiVersion = 'v1'; kind = 'ServiceAccount'; metadata = @{ name = 'operator'; namespace = 'srelab' } },
        @{ apiVersion = 'rbac.authorization.k8s.io/v1'; kind = 'Role'; metadata = @{ name = 'pod-reader'; namespace = 'srelab' }; rules = @(@{ apiGroups = @(''); resources = @('pods', 'pods/log'); verbs = @('get', 'list', 'watch') }) },
        @{ apiVersion = 'rbac.authorization.k8s.io/v1'; kind = 'RoleBinding'; metadata = @{ name = 'operator-reader'; namespace = 'srelab' }; subjects = @(@{ kind = 'ServiceAccount'; name = 'operator'; namespace = 'srelab' }); roleRef = @{ apiGroup = 'rbac.authorization.k8s.io'; kind = 'Role'; name = 'pod-reader' } },
        @{ apiVersion = 'apps/v1'; kind = 'Deployment'; metadata = @{ name = 'probe'; namespace = 'srelab' }; spec = @{
            replicas = 1; selector = @{ matchLabels = @{ app = 'srelab-probe' } }; template = @{
                metadata = @{ labels = @{ app = 'srelab-probe' } }; spec = @{
                    containers = @(@{
                        name = 'probe'; image = 'curlimages/curl:8.12.1'; command = @('/bin/sh', '-c')
                        args = @('while true; do for url in http://web http://backend.srelab.internal:8081/health; do code=$(curl -s -o /dev/null --max-time 4 -w "%{http_code}" "$url") || true; echo "SRELAB url=$url status=$code"; done; sleep 15; done')
                        resources = @{ requests = @{ cpu = '10m'; memory = '16Mi' }; limits = @{ cpu = '100m'; memory = '64Mi' } }
                    })
                }
            }
        } }
    ) + $webResources
}
$path = Join-Path $script:StateDirectory 'baseline-workloads.json'
Write-LabJson $path $manifest
Invoke-LabKube -File $path -Command 'kubectl apply -f baseline-workloads.json && kubectl -n srelab rollout status deployment/web --timeout=180s && kubectl -n srelab rollout status deployment/probe --timeout=180s'
Write-Host 'Workloads initialized. Run Test-Lab.ps1 before any fault injection.'
} finally { $maintenance.Dispose() }