$ErrorActionPreference = 'Stop'
$manifest = & "$PSScriptRoot/../scripts/Get-PublicShopManifest.ps1"
$service = @($manifest.items | Where-Object kind -eq 'Service')[0]
if ($service.spec.type -ne 'LoadBalancer' -or ($service.spec.ports.port -join ',') -ne '80,443') { throw 'Expected only public HTTP/HTTPS ports.' }
$deployment = @($manifest.items | Where-Object kind -eq 'Deployment')[0]
if ($deployment.spec.template.spec.automountServiceAccountToken -ne $false) { throw 'Gateway must not have Kubernetes credentials.' }
if ($deployment.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation -ne $false) { throw 'Gateway must not escalate privileges.' }
$config = @($manifest.items | Where-Object kind -eq 'ConfigMap')[0].data.Caddyfile
if ($config -match 'path .*/health|path .*/api/status|path .*/api/operations') { throw 'Private operations must not be public routes.' }
if ($config -notmatch 'max_size 8KB' -or $config -notmatch 'respond "Not found" 404') { throw 'Expected request limits and deny-by-default routes.' }
$page = Get-Content "$PSScriptRoot/../workload/frontend/shop.html" -Raw
if ($page -notmatch "addEventListener\('visibilitychange'" -or $page -notmatch 'refresh\(\); \}, 30000\)') { throw 'Images must refresh before lease expiry and on tab visibility.' }
Write-Host 'Public shop manifest and refresh checks passed.'