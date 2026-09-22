[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^/api/shop/(catalog|media|checkout|orders/[0-9a-f-]{36})$')][string]$Route,
    [ValidateSet('GET', 'POST')][string]$Method = 'GET'
)
. "$PSScriptRoot/Common.ps1"
if (($Route -eq '/api/shop/checkout') -ne ($Method -eq 'POST')) { throw 'Invalid shop method.' }
$bodyArgument = ''
if ($Method -eq 'POST') {
    $body = [Console]::In.ReadToEnd()
    if ([Text.Encoding]::UTF8.GetByteCount($body) -gt 8192) { throw 'Shop request is too large.' }
    $null = $body | ConvertFrom-Json
    $encodedBody = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body))
    $bodyArgument = "echo $encodedBody | base64 -d | "
}
$dataFlag = if ($Method -eq 'POST') { '--data-binary @-' } else { '' }
$command = "kubectl -n srelab exec deployment/probe -- sh -c '${bodyArgument}curl -sS --max-time 45 -X $Method -H Content-Type:application/json -H Origin:http://web $dataFlag -w __SHOP_STATUS__%{http_code} http://web$Route'"
$output = Invoke-LabKube -Command $command
$match = [regex]::Match($output, '(?s)^(.*)__SHOP_STATUS__(\d{3})\s*$')
if (-not $match.Success) { throw 'No conclusive shop response.' }
$status = [int]$match.Groups[2].Value
if ($status -lt 200 -or $status -gt 599) { throw 'Shop transport failed.' }
@{ status = $status; body = ($match.Groups[1].Value | ConvertFrom-Json -Depth 30) } | ConvertTo-Json -Depth 40 -Compress