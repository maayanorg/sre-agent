Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Subscription = '15ba7e94-568d-4ba9-bb5d-29ed107ac109'
$script:ResourceGroup = 'rg-srelab-swedencentral-001'
$script:NodeResourceGroup = 'rg-srelab-aksnodes-swedencentral-001'
$script:Location = 'swedencentral'
$script:Root = Split-Path $PSScriptRoot -Parent
$script:StateDirectory = Join-Path $script:Root '.state'
$script:GroupId = "/subscriptions/$script:Subscription/resourceGroups/$script:ResourceGroup"
$script:Tags = @('Project=SRE-Day', 'Purpose=IncidentResponseLab', 'Environment=Demo', 'Owner=mluxemburg', 'Lifecycle=ReusableEvent', 'ManagedBy=Bicep')

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Raw)
    $output = & az @Arguments --subscription $script:Subscription --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: az $($Arguments[0..([Math]::Min(2, $Arguments.Length - 1))] -join ' ')" }
    if ($Raw) { return ($output -join "`n") }
    if ($output) { return ($output -join "`n" | ConvertFrom-Json -Depth 100) }
}

function Write-LabJson {
    param([string]$Path, [object]$Value)
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force
    $json = $Value | ConvertTo-Json -Depth 100
    $temporary = "$Path.$([guid]::NewGuid()).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    } finally { if (Test-Path $temporary) { Remove-Item $temporary } }
}

function Assert-Lab {
    $group = Invoke-Az @('group', 'show', '-n', $script:ResourceGroup)
    if ($group.id -ine $script:GroupId -or $group.tags.Project -ne 'SRE-Day' -or $group.tags.Purpose -ne 'IncidentResponseLab') {
        throw 'Refusing operation: resource group identity or lab tags do not match.'
    }
}

function Get-Lab {
    Assert-Lab
    $deployment = Invoke-Az @('deployment', 'group', 'show', '-g', $script:ResourceGroup, '-n', 'srelab-baseline')
    if ($deployment.properties.provisioningState -ne 'Succeeded') { throw 'Baseline deployment has not succeeded.' }
    return $deployment.properties.outputs.lab.value
}

function Invoke-LabRest {
    param([string]$Method = 'GET', [Parameter(Mandatory)][string]$Id, [string]$Api = '2024-05-01', [object]$Body)
    if (-not $Id.StartsWith("$script:GroupId/", [StringComparison]::OrdinalIgnoreCase)) { throw "Resource outside lab scope: $Id" }
    $arguments = @('rest', '--method', $Method, '--url', "https://management.azure.com${Id}?api-version=$Api")
    $temp = Join-Path $script:StateDirectory "request-$([guid]::NewGuid()).json"
    try {
        if ($null -ne $Body) {
            Write-LabJson $temp $Body
            $arguments += @('--body', "@$temp")
        }
        Invoke-Az $arguments
    } finally { if (Test-Path $temp) { Remove-Item $temp } }
}

function Invoke-LabVm {
    param([string]$Command, [ValidateSet('client', 'backend')][string]$Target = 'client')
    $mutex = [Threading.Mutex]::new($false, "srelab-$script:Subscription-$Target-runcommand")
    $acquired = $false
    $scriptFile = $null
    try {
    $acquired = $mutex.WaitOne(120000)
    if (-not $acquired) { throw 'Another local VM command is still running; retry later.' }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Command.Replace("`r`n", "`n")))
    $shell = "echo '$encoded' | base64 -d | bash; rc=`$?; echo SRELAB_EXIT=`$rc; exit `$rc"
    $scriptFile = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($scriptFile, $shell, [Text.UTF8Encoding]::new($false))
    $result = Invoke-Az @('vm', 'run-command', 'invoke', '-g', $script:ResourceGroup, '-n', "vm-srelab-$Target-swc-001", '--command-id', 'RunShellScript', '--scripts', "@$scriptFile")
    $text = ($result.value | ForEach-Object { $_.message }) -join "`n"
    if ($text -notmatch 'SRELAB_EXIT=0(\s|$)') { throw "VM command failed or completion marker missing: $text" }
    return $text
    } finally { if ($scriptFile -and (Test-Path $scriptFile)) { Remove-Item $scriptFile }; if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Get-OperatorCheckCommand {
    return @'
set -e
server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
authority=$(mktemp)
trap 'rm -f "$authority"' EXIT
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "$authority"
if [ ! -s "$authority" ]; then
    authoritySource=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')
    test -n "$authoritySource"
    cat "$authoritySource" > "$authority"
fi
test -s "$authority"
token=$(kubectl -n srelab create token operator --duration=10m)
set +e
answer=$(kubectl --kubeconfig=/dev/null --server="$server" --certificate-authority="$authority" --token="$token" -n srelab auth can-i list pods 2>/dev/null)
result=$?
unset token
if [ "$answer" = yes ] && [ "$result" -eq 0 ]; then
    echo 'SRELAB_OPERATOR=healthy'
elif [ "$result" -eq 1 ]; then
    case "$answer" in no|no\ -*) echo 'SRELAB_OPERATOR=failed';; *) echo 'SRELAB_OPERATOR=unknown';; esac
else
    echo 'SRELAB_OPERATOR=unknown'
fi
'@
}

function Invoke-LabKube {
    param([string]$Command, [string]$File)
    $mutex = [Threading.Mutex]::new($false, "srelab-$script:Subscription-aks-runcommand")
    $acquired = $false
    try {
    $acquired = $mutex.WaitOne(120000)
    if (-not $acquired) { throw 'Another local AKS command is still running; retry later.' }
    $arguments = @('aks', 'command', 'invoke', '-g', $script:ResourceGroup, '-n', 'aks-srelab-swc-001', '--command', $Command)
    if ($File) { $arguments += @('--file', $File) }
    $result = Invoke-Az $arguments
    if ($result.exitCode -ne 0) { throw "AKS command failed: $($result.logs)" }
    return $result.logs
    } finally { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Enter-LabMaintenance {
    $null = New-Item -ItemType Directory -Path $script:StateDirectory -Force
    $handle = [IO.File]::Open((Join-Path $script:StateDirectory 'incident.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        foreach ($name in @('active-incident.json', 'web-outage.json')) {
            if (Test-Path (Join-Path $script:StateDirectory $name)) { throw 'Restore the recorded incident before changing the baseline.' }
        }
        return $handle
    } catch { $handle.Dispose(); throw }
}