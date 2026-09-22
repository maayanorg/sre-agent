[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Deploy', 'Status', 'Remove')][string]$Action = 'Status')
. "$PSScriptRoot/Common.ps1"
$null = Get-Lab
if ($Action -eq 'Status') {
    Invoke-LabKube -Command 'kubectl -n srelab get deployment/public-shop service/public-shop pvc/public-shop-certificates -o wide'
    return
}
$maintenance = Enter-LabMaintenance
try {
    $subnet = Invoke-Az @('network', 'vnet', 'subnet', 'show', '-g', 'rg-srelab-swedencentral-001', '--vnet-name', 'vnet-srelab-aks-swc-001', '-n', 'snet-aks')
    $subnetNsg = $subnet.PSObject.Properties['networkSecurityGroup']
    $nsg = $null
    $rule = $null
    $ruleName = 'AllowPublicShop'
    $ruleDescription = 'SRE-Day public-shop managed HTTP and HTTPS ingress'
    if ($subnetNsg -and $subnetNsg.Value) {
        $nsg = Invoke-Az @('network', 'nsg', 'show', '--ids', $subnetNsg.Value.id)
        $rule = @($nsg.securityRules | Where-Object name -eq $ruleName)
        if ($rule.Count -gt 0 -and $rule[0].description -ne $ruleDescription) { throw 'Refusing to change an existing unmanaged AllowPublicShop rule.' }
        if (@($nsg.securityRules | Where-Object { $_.priority -eq 300 -and $_.name -ne $ruleName }).Count -gt 0) { throw 'Subnet NSG priority 300 is already in use.' }
    }
    if ($Action -eq 'Remove') {
        if ($PSCmdlet.ShouldProcess('srelab/public-shop', 'Remove public Service and HTTPS gateway; retain certificate PVC')) {
            if ($nsg -and $rule.Count -gt 0) {
                $null = Invoke-Az @('network', 'nsg', 'rule', 'delete', '-g', $nsg.resourceGroup, '--nsg-name', $nsg.name, '-n', $ruleName)
            }
            Invoke-LabKube -Command 'kubectl -n srelab delete service public-shop --ignore-not-found && kubectl -n srelab delete deployment public-shop --ignore-not-found'
        }
        return
    }
    if ($PSCmdlet.ShouldProcess('srelab/public-shop', 'Deploy public HTTPS demo gateway and certificate storage')) {
        $manifest = & "$PSScriptRoot/Get-PublicShopManifest.ps1"
        $config = @($manifest.items | Where-Object kind -eq 'ConfigMap')[0]
        $deployment = @($manifest.items | Where-Object kind -eq 'Deployment')[0]
        $spec = $deployment.spec.template.spec | ConvertTo-Json -Depth 40 | ConvertFrom-Json -AsHashtable
        $spec.restartPolicy = 'Never'
        $spec.containers[0].command = @('caddy', 'validate', '--config', '/etc/caddy/Caddyfile', '--adapter', 'caddyfile')
        $spec.containers[0].Remove('readinessProbe')
        $spec.containers[0].Remove('livenessProbe')
        $spec.volumes[1] = @{ name = 'data'; emptyDir = @{} }
        $validation = @{ apiVersion = 'v1'; kind = 'List'; items = @($config; @{ apiVersion = 'v1'; kind = 'Pod'; metadata = @{ name = 'public-shop-config-check'; namespace = 'srelab' }; spec = $spec }) }
        $validationPath = Join-Path $script:StateDirectory 'public-shop-validation.json'
        Write-LabJson $validationPath $validation
        Invoke-LabKube -File $validationPath -Command 'kubectl -n srelab delete pod public-shop-config-check --ignore-not-found && kubectl apply -f public-shop-validation.json && { kubectl -n srelab wait pod/public-shop-config-check --for=jsonpath={.status.phase}=Succeeded --timeout=180s || { kubectl -n srelab logs public-shop-config-check; exit 1; }; } && kubectl -n srelab logs public-shop-config-check && kubectl -n srelab delete pod public-shop-config-check'
        $path = Join-Path $script:StateDirectory 'public-shop.json'
        Write-LabJson $path $manifest
        Invoke-LabKube -File $path -Command 'kubectl apply --dry-run=server -f public-shop.json && kubectl apply -f public-shop.json && kubectl -n srelab rollout status deployment/public-shop --timeout=240s && kubectl -n srelab get service public-shop -o wide'
        if ($nsg) {
            Invoke-LabKube -Command 'kubectl -n srelab wait service/public-shop --for=jsonpath={.status.loadBalancer.ingress} --timeout=240s'
            $addresses = @(Invoke-Az @('network', 'public-ip', 'list', '-g', 'rg-srelab-aksnodes-swedencentral-001', '--query', "[?dnsSettings.domainNameLabel=='srelab-shop-2d6ikhr5ewo6o'].ipAddress"))
            if ($addresses.Count -ne 1 -or -not $addresses[0]) { throw 'Expected exactly one public shop IP before opening subnet ingress.' }
            $null = Invoke-Az @('network', 'nsg', 'rule', 'create', '-g', $nsg.resourceGroup, '--nsg-name', $nsg.name, '-n', $ruleName, '--priority', '300', '--direction', 'Inbound', '--access', 'Allow', '--protocol', 'Tcp', '--source-address-prefixes', 'Internet', '--source-port-ranges', '*', '--destination-address-prefixes', $addresses[0], '--destination-port-ranges', '80', '443', '--description', $ruleDescription)
        }
        Write-Host 'Public URL: https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com'
        Write-Host 'DNS and certificate issuance must succeed before HTTPS is ready. Use Status and verify HTTPS without bypassing certificate validation.'
    }
} finally { $maintenance.Dispose() }