$script:ScenarioCatalog = [ordered]@{
    'BackendService' = @{ kind = 'VmService'; target = 'backend'; service = 'srelab'; check = 'backend'; title = 'Backend service stopped' }
    'ClientService' = @{ kind = 'VmService'; target = 'client'; service = 'srelab'; check = 'client'; title = 'Client service stopped' }
    'BackendVm' = @{ kind = 'VmPower'; target = 'backend'; check = 'backend'; title = 'Backend VM deallocated' }
    'ClientVm' = @{ kind = 'VmPower'; target = 'client'; check = 'client'; title = 'Client VM deallocated' }
    'DnsRecordMissing' = @{ kind = 'ArmDelete'; path = '/providers/Microsoft.Network/privateDnsZones/srelab.internal/A/backend'; api = '2020-06-01'; check = 'backend'; title = 'Backend DNS record missing' }
    'DnsRecordWrong' = @{ kind = 'ArmUpdate'; path = '/providers/Microsoft.Network/privateDnsZones/srelab.internal/A/backend'; api = '2020-06-01'; check = 'backend'; title = 'Backend DNS points to unused address' }
    'DnsLinkMissing' = @{ kind = 'ArmDelete'; path = '/providers/Microsoft.Network/privateDnsZones/srelab.internal/virtualNetworkLinks/link-services'; api = '2020-06-01'; check = 'client'; title = 'Services VNet DNS link missing' }
    'RouteBlackhole' = @{ kind = 'ArmCreate'; path = '/providers/Microsoft.Network/routeTables/rt-srelab-client-swc-001/routes/srelab-incident'; api = '2024-05-01'; check = 'client'; title = 'Client backend route blackholed' }
    'RouteWrongHop' = @{ kind = 'ArmCreate'; path = '/providers/Microsoft.Network/routeTables/rt-srelab-client-swc-001/routes/srelab-incident'; api = '2024-05-01'; check = 'client'; title = 'Client backend route has wrong next hop' }
    'NsgBackend' = @{ kind = 'ArmUpdate'; path = '/providers/Microsoft.Network/networkSecurityGroups/nsg-srelab-workload-swc-001/securityRules/AllowLabHttp'; api = '2024-05-01'; check = 'backend'; title = 'NSG blocks backend HTTP' }
    'BlobDns' = @{ kind = 'ArmDelete'; path = '/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-services'; api = '2020-06-01'; check = 'storage'; title = 'Blob private DNS link missing' }
    'VaultDns' = @{ kind = 'ArmDelete'; path = '/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net/virtualNetworkLinks/link-services'; api = '2020-06-01'; check = 'vault'; title = 'Vault private DNS link missing' }
    'BlobEndpoint' = @{ kind = 'Endpoint'; target = 'blob'; check = 'storage'; title = 'Blob private endpoint removed' }
    'VaultEndpoint' = @{ kind = 'Endpoint'; target = 'vault'; check = 'vault'; title = 'Vault private endpoint removed' }
    'StorageRbac' = @{ kind = 'Role'; assignment = 'blobAssignmentId'; check = 'storage'; title = 'VM identity Blob role removed' }
    'VaultRbac' = @{ kind = 'Role'; assignment = 'vaultAssignmentId'; check = 'vault'; title = 'VM identity Vault role removed' }
    'ArmRbac' = @{ kind = 'Role'; assignment = 'readerAssignmentId'; check = 'arm'; title = 'VM identity RG Reader role removed' }
    'KubeRbac' = @{ kind = 'KubeRole'; check = 'operator'; title = 'Kubernetes operator pod access removed' }
    'AksBadImage' = @{ kind = 'KubeDeployment'; check = 'web'; title = 'Web image cannot be pulled' }
    'AksCrashLoop' = @{ kind = 'KubeDeployment'; check = 'web'; title = 'Web process exits repeatedly' }
    'AksReadiness' = @{ kind = 'KubeDeployment'; check = 'web'; title = 'Web readiness probe fails' }
    'AksScheduling' = @{ kind = 'KubeDeployment'; check = 'web'; title = 'Web pod cannot be scheduled' }
    'AksOom' = @{ kind = 'KubeDeployment'; check = 'web'; title = 'Web container exceeds memory limit' }
    'DiskFull' = @{ kind = 'VmFile'; target = 'backend'; check = 'backend'; title = 'Backend lab data filesystem full' }
    'BadConfig' = @{ kind = 'VmFile'; target = 'backend'; check = 'backend'; title = 'Backend release configuration invalid' }
    'CpuPressure' = @{ kind = 'VmStress'; target = 'backend'; check = 'cpu'; title = 'Backend bounded CPU pressure' }
    'MemoryPressure' = @{ kind = 'VmStress'; target = 'backend'; check = 'memory'; title = 'Backend bounded memory pressure' }
    'TelemetryGap' = @{ kind = 'VmService'; target = 'backend'; service = 'azuremonitoragent'; check = 'ama'; title = 'Backend monitoring agent stopped' }
}

function Get-ScenarioDefinition {
    param([string]$Scenario)
    if (-not $script:ScenarioCatalog.Contains($Scenario)) { throw "Unknown scenario: $Scenario" }
    return $script:ScenarioCatalog[$Scenario]
}