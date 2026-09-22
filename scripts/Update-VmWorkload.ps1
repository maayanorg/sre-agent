[CmdletBinding(SupportsShouldProcess)]
param()
. "$PSScriptRoot/Common.ps1"
$null = Get-Lab
$maintenance = Enter-LabMaintenance
try {
    $source = [IO.File]::ReadAllText((Join-Path $script:Root 'workload/server.js'))
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($source.Replace("`r`n", "`n")))
    $shopSource = [IO.File]::ReadAllText((Join-Path $script:Root 'workload/shop.cjs'))
    $shopEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($shopSource.Replace("`r`n", "`n")))
    foreach ($target in @('client', 'backend')) {
        if ($PSCmdlet.ShouldProcess("vm-srelab-$target-swc-001", 'Update lab HTTP application and restart service')) {
            Invoke-LabVm -Target $target -Command "set -e; test -f /opt/srelab/bootstrap-complete; echo '$encoded' | base64 -d > /opt/srelab/server.js.new; echo '$shopEncoded' | base64 -d > /opt/srelab/shop.cjs.new; node --check < /opt/srelab/server.js.new; node --check < /opt/srelab/shop.cjs.new; chown srelab:srelab /opt/srelab/server.js.new /opt/srelab/shop.cjs.new; mv /opt/srelab/shop.cjs.new /opt/srelab/shop.cjs; mv /opt/srelab/server.js.new /opt/srelab/server.js; systemctl restart srelab"
        }
    }
} finally { $maintenance.Dispose() }