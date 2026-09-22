[CmdletBinding()]
param()
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'workload/frontend'
$server = Get-Content (Join-Path $source 'server.cjs') -Raw
$page = Get-Content (Join-Path $source 'index.html') -Raw
$shopPage = Get-Content (Join-Path $source 'shop.html') -Raw
$shopProxy = Get-Content (Join-Path $source 'shop-proxy.cjs') -Raw
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($server + $page + $shopPage + $shopProxy))).ToLowerInvariant().Substring(0, 12)
$configName = "srelab-frontend-$hash"
@{
    apiVersion = 'v1'; kind = 'List'; items = @(
        @{ apiVersion = 'v1'; kind = 'ConfigMap'; immutable = $true; metadata = @{ name = $configName; namespace = 'srelab'; labels = @{ app = 'srelab-web' } }; data = @{ 'server.cjs' = $server; 'index.html' = $page; 'shop.html' = $shopPage; 'shop-proxy.cjs' = $shopProxy } },
        @{ apiVersion = 'apps/v1'; kind = 'Deployment'; metadata = @{ name = 'web'; namespace = 'srelab' }; spec = @{
            replicas = 1; selector = @{ matchLabels = @{ app = 'srelab-web' } }; template = @{
                metadata = @{ labels = @{ app = 'srelab-web' }; annotations = @{ 'srelab/source-hash' = $hash } }; spec = @{
                    automountServiceAccountToken = $false
                    securityContext = @{ runAsNonRoot = $true; runAsUser = 1000; runAsGroup = 1000; seccompProfile = @{ type = 'RuntimeDefault' } }
                    containers = @(@{
                        name = 'web'; image = 'node:22-alpine'; command = @('node', '/app/server.cjs'); ports = @(@{ containerPort = 8080 })
                        resources = @{ requests = @{ cpu = '50m'; memory = '64Mi' }; limits = @{ cpu = '250m'; memory = '128Mi' } }
                        securityContext = @{ allowPrivilegeEscalation = $false; readOnlyRootFilesystem = $true; capabilities = @{ drop = @('ALL') } }
                        volumeMounts = @(@{ name = 'source'; mountPath = '/app'; readOnly = $true })
                        readinessProbe = @{ httpGet = @{ path = '/healthz'; port = 8080 }; initialDelaySeconds = 3; periodSeconds = 5 }
                        livenessProbe = @{ httpGet = @{ path = '/healthz'; port = 8080 }; initialDelaySeconds = 10; periodSeconds = 10 }
                    })
                    volumes = @(@{ name = 'source'; configMap = @{ name = $configName } })
                }
            }
        } },
        @{ apiVersion = 'v1'; kind = 'Service'; metadata = @{ name = 'web'; namespace = 'srelab' }; spec = @{ type = 'ClusterIP'; selector = @{ app = 'srelab-web' }; ports = @(@{ port = 80; targetPort = 8080 }) } }
    )
}