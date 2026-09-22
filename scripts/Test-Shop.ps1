[CmdletBinding()]
param([switch]$IncludeCheckout)
. "$PSScriptRoot/Common.ps1"
$null = Get-Lab
foreach ($route in @('catalog', 'media')) {
    $reply = & "$PSScriptRoot/Invoke-ShopRequest.ps1" -Route "/api/shop/$route" | ConvertFrom-Json -Depth 30
    if ($reply.status -ne 200) { throw "Shop $route failed." }
    if ($route -eq 'catalog' -and $reply.body.products.Count -ne 4) { throw 'Expected four products.' }
    if ($route -eq 'media' -and @($reply.body.images.PSObject.Properties).Count -ne 4) { throw 'Expected four Blob images.' }
}
if ($IncludeCheckout) {
    $body = @{ requestId = [guid]::NewGuid().ToString(); items = @(@{ id = 'watch'; quantity = 1 }) } | ConvertTo-Json -Compress
    $requestScript = Join-Path $PSScriptRoot 'Invoke-ShopRequest.ps1'
    $reply = $body | & pwsh -NoProfile -NonInteractive -File $requestScript -Route '/api/shop/checkout' -Method POST | ConvertFrom-Json -Depth 30
    if ($LASTEXITCODE -ne 0 -or $reply.status -ne 200 -or $reply.body.total -ne 8900 -or $reply.body.payment -ne 'simulated') { throw 'Demo checkout failed.' }
    $saved = & "$PSScriptRoot/Invoke-ShopRequest.ps1" -Route "/api/shop/orders/$($reply.body.id)" | ConvertFrom-Json -Depth 30
    if ($saved.status -ne 200 -or $saved.body.id -ne $reply.body.id) { throw 'Order was not readable after checkout.' }
    Write-Host "Persisted demo order verified: $($reply.body.id)"
}
Write-Host 'Shop catalog and Blob images verified.'