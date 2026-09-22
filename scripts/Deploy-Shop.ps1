[CmdletBinding(SupportsShouldProcess)]
param([switch]$DataAlreadySeeded)
. "$PSScriptRoot/Common.ps1"
$null = Get-Lab
if (-not $PSCmdlet.ShouldProcess($script:ResourceGroup, 'Seed shop data, update both VM services, deploy storefront and verify shop')) { return }
& (Join-Path $script:Root 'tests/Validate-Local.ps1')
if (-not $DataAlreadySeeded) { & "$PSScriptRoot/Initialize-ShopData.ps1" }
$source = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:Root 'workload/shop.cjs')))
$preflight = @'
set -e
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
echo '__SOURCE__' | base64 -d > "$temporary/shop.cjs"
node - "$temporary/shop.cjs" <<'NODE'
const {createAzureRead,products}=require(process.argv[2]);
const config=require('/opt/srelab/config.json');
const read=createAzureRead(()=>config);
(async()=>{
  for(const product of products){const bytes=await read('https://storage.azure.com/',`https://${config.storage}.blob.core.windows.net/lab/shop/${product.id}.jpg`,'bytes');if(bytes.length<100)throw new Error('Invalid asset');}
  const secret=await read('https://vault.azure.net',`https://${config.vault}.vault.azure.net/secrets/shop-demo-payment-key?api-version=7.4`);
  if(typeof secret.value!=='string'||secret.value.length<32)throw new Error('Invalid demo authorization configuration');
  console.log('Shop data preflight passed');
})().catch(()=>{console.error('Shop data preflight failed. Seed the private Blob assets and Vault secret before deployment.');process.exitCode=1;});
NODE
'@
Invoke-LabVm -Target client -Command $preflight.Replace('__SOURCE__', $source)
& "$PSScriptRoot/Update-VmWorkload.ps1"
& "$PSScriptRoot/Deploy-Frontend.ps1"
& "$PSScriptRoot/Test-Shop.ps1" -IncludeCheckout
Write-Host 'Shop deployed. Restart Start-DemoViewer.ps1 to load the new storefront.'