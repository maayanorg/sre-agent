[CmdletBinding()]
param([switch]$IncludeCheckout)
$ErrorActionPreference = 'Stop'
$base = 'https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com'
$page = Invoke-WebRequest "$base/" -TimeoutSec 45
if ($page.StatusCode -ne 200 -or $page.Content -notmatch 'Fieldnote' -or -not $page.Headers['Strict-Transport-Security']) { throw 'HTTPS storefront or security header missing.' }
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [Net.Http.HttpClient]::new($handler)
try {
    $redirect = $client.GetAsync($base.Replace('https:', 'http:') + '/').GetAwaiter().GetResult()
    if ([int]$redirect.StatusCode -notin @(301, 308) -or $redirect.Headers.Location.AbsoluteUri -ne "$base/") { throw 'HTTP must redirect to the public HTTPS URL.' }
    $redirect.Dispose()
} finally { $client.Dispose(); $handler.Dispose() }
$catalog = Invoke-RestMethod "$base/api/shop/catalog" -TimeoutSec 45
$media = Invoke-RestMethod "$base/api/shop/media" -TimeoutSec 45
if (@($catalog.products).Count -ne 4 -or @($media.images.PSObject.Properties).Count -ne 4) { throw 'Expected four products and images.' }
foreach ($image in $media.images.PSObject.Properties) {
    if ($image.Value -notmatch '^data:image/jpeg;base64,') { throw 'Invalid product image.' }
    $bytes = [Convert]::FromBase64String($image.Value.Substring(23))
    if ($bytes.Length -lt 100 -or $bytes[0] -ne 255 -or $bytes[1] -ne 216) { throw 'Invalid JPEG bytes.' }
}
foreach ($route in @('/health', '/api/status', '/api/operations', '/shop/catalog', '/api/shop/execute')) {
    $response = Invoke-WebRequest "$base$route" -SkipHttpErrorCheck -TimeoutSec 45
    if ($response.StatusCode -ne 404) { throw "Private or unsupported route exposed: $route" }
}
$denied = Invoke-WebRequest "$base/api/shop/checkout" -Method Post -ContentType 'application/json' -Headers @{ Origin = 'https://example.invalid' } -Body '{}' -SkipHttpErrorCheck -TimeoutSec 45
if ($denied.StatusCode -ne 403) { throw 'Cross-origin checkout must be denied.' }
$orderId = $null
if ($IncludeCheckout) {
    $orderId = [guid]::NewGuid().ToString()
    $body = @{ requestId = $orderId; items = @(@{ id = 'watch'; quantity = 1 }) } | ConvertTo-Json -Depth 5 -Compress
    $order = Invoke-RestMethod "$base/api/shop/checkout" -Method Post -ContentType 'application/json' -Headers @{ Origin = $base } -Body $body -TimeoutSec 45
    $saved = Invoke-RestMethod "$base/api/shop/orders/$orderId" -TimeoutSec 45
    if ($order.id -ne $orderId -or $saved.id -ne $orderId -or $saved.total -ne 8900) { throw 'Public checkout or persisted lookup failed.' }
}
[pscustomobject]@{ url = $base; https = 'valid'; products = 4; images = 4; privateRoutes = 'blocked'; crossOriginCheckout = 'blocked'; orderId = $orderId; observedAt = [DateTime]::UtcNow.ToString('o') }