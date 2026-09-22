[CmdletBinding()]
param([Parameter(Mandatory)][string]$Scenario)
. "$PSScriptRoot/ScenarioEngine.ps1"
$definition = Get-ScenarioDefinition $Scenario
$lab = Get-Lab
switch ($definition.kind) {
    { $_ -in @('ArmDelete', 'ArmUpdate', 'ArmCreate') } {
        @(Get-ArmChild "$script:GroupId$($definition.path)" $definition.api) | ConvertTo-Json -Depth 30
        Invoke-LabKube -Command 'kubectl -n srelab logs deployment/web --tail=5'
    }
    'Role' { @(Get-ArmChild $lab.($definition.assignment) '2022-04-01') | ConvertTo-Json -Depth 20 }
    'Endpoint' {
        Invoke-LabRest -Id "$script:GroupId/providers/Microsoft.Network/privateEndpoints/pe-srelab-$($definition.target)-swc-001" | ConvertTo-Json -Depth 30
    }
    { $_ -in @('KubeDeployment', 'KubeRole') } {
        Invoke-LabKube -Command 'kubectl -n srelab get deployment web; kubectl -n srelab get pods -l app=srelab-web; kubectl -n srelab get events --sort-by=.lastTimestamp | tail -15; kubectl -n srelab get rolebinding operator-reader -o json'
        if ($definition.kind -eq 'KubeRole') { Invoke-ScenarioShell (Get-OperatorCheckCommand) }
    }
    'VmPower' {
        $view = Invoke-Az @('vm', 'get-instance-view', '-g', $script:ResourceGroup, '-n', "vm-srelab-$($definition.target)-swc-001")
        $view.instanceView.statuses
    }
    default {
        Invoke-LabVm -Target $definition.target -Command 'systemctl is-active srelab azuremonitoragent; df -h /mnt/srelab-data; free -m; vmstat 1 2; journalctl -u srelab --no-pager -n 8; systemctl show srelab-incident-cpu.service srelab-incident-memory.service -p ActiveState -p MemoryCurrent; true'
    }
}