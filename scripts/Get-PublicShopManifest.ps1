[CmdletBinding()]
param()
$dnsLabel = 'srelab-shop-2d6ikhr5ewo6o'
$hostName = "$dnsLabel.swedencentral.cloudapp.azure.com"
$config = Get-Content (Join-Path $PSScriptRoot '../workload/frontend/Caddyfile') -Raw
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($config))).ToLowerInvariant().Substring(0, 12)
$configName = "srelab-public-shop-$hash"
@{
    apiVersion = 'v1'; kind = 'List'; items = @(
        @{ apiVersion = 'v1'; kind = 'ConfigMap'; immutable = $true; metadata = @{ name = $configName; namespace = 'srelab'; labels = @{ app = 'srelab-public-shop' } }; data = @{ Caddyfile = $config } },
        @{ apiVersion = 'v1'; kind = 'PersistentVolumeClaim'; metadata = @{ name = 'public-shop-certificates'; namespace = 'srelab' }; spec = @{ accessModes = @('ReadWriteOnce'); storageClassName = 'managed-csi'; resources = @{ requests = @{ storage = '1Gi' } } } },
        @{ apiVersion = 'apps/v1'; kind = 'Deployment'; metadata = @{ name = 'public-shop'; namespace = 'srelab' }; spec = @{
            replicas = 1; strategy = @{ type = 'Recreate' }; selector = @{ matchLabels = @{ app = 'srelab-public-shop' } }; template = @{
                metadata = @{ labels = @{ app = 'srelab-public-shop' } }; spec = @{
                    automountServiceAccountToken = $false
                    securityContext = @{ runAsNonRoot = $true; runAsUser = 1000; runAsGroup = 1000; fsGroup = 1000; seccompProfile = @{ type = 'RuntimeDefault' } }
                    containers = @(@{
                        name = 'https'; image = 'caddy:2.10.2-alpine'; command = @('caddy', 'run', '--config', '/etc/caddy/Caddyfile', '--adapter', 'caddyfile')
                        env = @(@{ name = 'SHOP_HOST'; value = $hostName }; @{ name = 'XDG_DATA_HOME'; value = '/data' }; @{ name = 'XDG_CONFIG_HOME'; value = '/config' })
                        ports = @(@{ name = 'http'; containerPort = 8080 }; @{ name = 'https'; containerPort = 8443 }; @{ name = 'health'; containerPort = 8082 })
                        resources = @{ requests = @{ cpu = '25m'; memory = '32Mi' }; limits = @{ cpu = '250m'; memory = '128Mi' } }
                        securityContext = @{ allowPrivilegeEscalation = $false; readOnlyRootFilesystem = $true; capabilities = @{ drop = @('ALL'); add = @('NET_BIND_SERVICE') } }
                        volumeMounts = @(@{ name = 'source'; mountPath = '/etc/caddy'; readOnly = $true }; @{ name = 'data'; mountPath = '/data' }; @{ name = 'config'; mountPath = '/config' })
                        readinessProbe = @{ httpGet = @{ path = '/healthz'; port = 8082 }; periodSeconds = 5 }
                        livenessProbe = @{ httpGet = @{ path = '/healthz'; port = 8082 }; initialDelaySeconds = 10; periodSeconds = 10 }
                    })
                    volumes = @(@{ name = 'source'; configMap = @{ name = $configName } }; @{ name = 'data'; persistentVolumeClaim = @{ claimName = 'public-shop-certificates' } }; @{ name = 'config'; emptyDir = @{} })
                }
            }
        } },
        @{ apiVersion = 'v1'; kind = 'Service'; metadata = @{ name = 'public-shop'; namespace = 'srelab'; annotations = @{ 'service.beta.kubernetes.io/azure-dns-label-name' = $dnsLabel } }; spec = @{
            type = 'LoadBalancer'; externalTrafficPolicy = 'Cluster'; selector = @{ app = 'srelab-public-shop' }
            ports = @(@{ name = 'http'; port = 80; targetPort = 8080 }; @{ name = 'https'; port = 443; targetPort = 8443 })
        } }
    )
}