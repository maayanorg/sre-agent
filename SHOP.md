# Fieldnote Shop Migration

## Current Status

**Public HTTPS shop verified on 2026-09-22:** https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com/

No localhost process or Azure login is needed to browse. AKS serves the storefront through a Caddy HTTPS gateway; the two Azure VMs run the shop services. Four images remain in private Blob Storage, the simulated payment key remains in private Key Vault, and orders persist on the backend VM filesystem. Approved temporary setup roles were removed and their absence verified after seeding. No permanent write roles were added.

## Public Access

```powershell
./scripts/Set-PublicShop.ps1 -Action Status
./scripts/Test-PublicShop.ps1 -IncludeCheckout
# Reconcile the gateway, certificate PVC and scoped subnet NSG rule:
./scripts/Set-PublicShop.ps1 -Action Deploy
# Remove public ingress and gateway, retaining certificate storage:
./scripts/Set-PublicShop.ps1 -Action Remove
```

Deploy validates Caddy in an unexposed pod before applying the LoadBalancer Service. Ports 80 and 443 are public; HTTP redirects to trusted HTTPS. The subnet NSG rule is restricted to the actual shop public IP and those ports. Remove deletes only the script-owned rule and gateway resources, not unrelated NSG rules. Do not modify the AKS-managed node NSG manually. Retained certificate storage avoids unnecessary certificate reissuance on redeployment.

Only `/` and allowlisted `/api/shop/*` requests reach the app. `/health`, `/api/status`, `/api/operations` and arbitrary backend paths return 404 publicly. The private web Service, VM addresses, Blob/Vault endpoints and AKS API remain private. Faults are still injected/reset using authenticated operator scripts, never browser controls.

The anonymous demo proxy limits each web process to 120 accepted API requests and 10 checkouts per minute, with 8 concurrent requests and 8 KB request bodies. These global limits are not per-user quotas or a WAF; a busy audience can receive 429 responses. This is not a production store. Public IP/load-balancer usage and a 1 GiB managed certificate disk add ongoing charges. Removing the gateway retains that disk; stopping compute does not remove all lab charges.

The local preview runs at http://127.0.0.1:8092 with an explicit fixture banner. It uses local images and a local simulated authorization key, not Azure. Its orders are stored under `.state/shop-preview/orders`. This is UI/behavior evidence, not proof of Azure fault scenarios.

## Resource Dependencies

| Component | Shop responsibility | Actual dependency after deployment |
|---|---|---|
| AKS web | Storefront, cart interface and API proxy | Requests reach the client VM on port 8080 |
| Client VM | Read product images; forward catalog and order calls | Private Blob endpoint and `backend.srelab.internal:8081` |
| Backend VM | Product catalog, authoritative pricing, demo checkout, order lookup | Key Vault secret and local order filesystem |
| Blob Storage | Four product JPEGs in private container `lab`, under `shop/` | Images are fetched with managed identity on every media API request |
| Key Vault | `shop-demo-payment-key` | Read for each new checkout; HMAC authorizes a simulated payment |
| Backend filesystem | Order records under `/mnt/srelab-data/orders` | Checkout succeeds only after an order record is written and file-synced |
| Azure/Kubernetes permissions and monitoring | Operator access and observability | Not artificial prerequisites for customer checkout |

The catalog is a fixed four-product assortment with server-side prices, not a stock reservation or inventory management system. Payments, shipping and fulfillment are simulated; no card details or personal information are collected. Orders have unguessable UUID references but no customer authentication. Public access is for the lab demonstration only, not production commerce or sensitive data.

New checkout requests use an idempotency reference retained in browser storage. Retries use the same reference; conflicting baskets are rejected. Confirmed orders can be retrieved by reference and survive service restarts on the same VM disk. There is no backup, replicated database or power-loss durability guarantee. Lost responses must be retried before starting another checkout. Browser state must not be manually cleared during an ambiguous checkout.

## Local Preview

```powershell
./scripts/Get-ShopAssets.ps1
./tests/Validate-Local.ps1
node ./scripts/preview-shop.cjs 8092
```

Product image sources are recorded in [workload/shop-assets.json](workload/shop-assets.json). The photos are illustrative Unsplash assets, downloaded at a constrained size; see the [Unsplash license](https://unsplash.com/license). They are not claims about actual inventory or product brands. Each JPEG must be under 100 KB. The live application has no local image fallback.

## Private Deployment

1. Restore any active incident. Do not remove saved recovery records to bypass guards.
2. Start both lab VMs and AKS if stopped. Use the authorized lab operator identity. The following seed step temporarily assigns Blob Data Contributor on the `lab` container and Key Vault Secrets Officer on the lab vault to the VM identity.
3. Run the approved Azure-internal seed step:

   ```powershell
   ./scripts/Initialize-ShopDataInAzure.ps1
   ```

   Images download and the demo secret is generated inside the client VM. Managed identity accesses the private services; secret values are not returned. Differing images are not overwritten and an existing secret is not rotated. Role propagation retries are bounded. Each temporary assignment ID is recorded before creation and deleted in `finally`, with absence verified. After an interruption, run `./scripts/Initialize-ShopDataInAzure.ps1 -CleanupOnly` before retrying. Never delete its recovery record to bypass cleanup. Do not enable debug logging or PowerShell tracing around secret handling. The older `Initialize-ShopData.ps1` remains an alternative for an already-authorized private workstation; it assigns no roles.

4. From the authorized lab operator workstation, after seeding:

   ```powershell
   ./scripts/Deploy-Shop.ps1 -DataAlreadySeeded
   ```

   This runs local checks, reads the actual assets and secret from the client VM before changing services, updates both VM payloads, deploys the AKS frontend, and verifies catalog/images plus a persisted demo order. These steps have passed live. It does not redeploy the infrastructure. If interrupted after a partial update, diagnose the failed step before retrying; there is no automatic deployment rollback. Without `-DataAlreadySeeded`, Deploy-Shop uses the older workstation seed path.

5. Deploy public access and verify the baseline:

   ```powershell
   ./scripts/Set-PublicShop.ps1 -Action Deploy
   ./scripts/Test-PublicShop.ps1 -IncludeCheckout
   ./scripts/Test-Lab.ps1 -IncludeTelemetry
   ```

Open the public URL above for the shop. For the optional private operator dashboard, run `./scripts/Start-DemoViewer.ps1 -Port 8091` and open http://127.0.0.1:8091/health. Restart a viewer after frontend changes because it caches HTML at startup. Run only one viewer to avoid competing management requests. Each `-IncludeCheckout` run creates one real persisted demo order, never a real payment.

The optional laptop relay is localhost-only and uses AKS Run Command, so it can take tens of seconds or minutes. The public shop does not use that relay: requests pass directly from the Azure Load Balancer through Caddy and the AKS web Service to the VMs. Checkout remains restricted to same-origin JSON requests.

## Fault Impact Matrix

The table maps implemented paths to expected impact. **BlobEndpoint, VaultEndpoint and DiskFull have live shop failure/recovery evidence; the remaining rows are not claimed as shop rehearsals.** Existing scenario Verify commands primarily check health/operations symptoms; they do not prove that a customer order or image request failed. Use [SCENARIOS.md](SCENARIOS.md) for injection, inspection and saved-state reset, then check the named shop action and recovery.

Endpoint scenarios capture the endpoint and DNS bindings, delete the endpoint, and recreate both on reset. Azure cannot re-approve a rejected connection. Dynamic endpoint IPs and provider connection/NIC IDs may change on recreation; applications use DNS, not these IDs. Storage data and vault secrets are retained. Do not change the endpoint concurrently with a rehearsal.

| Scenario | Expected customer or operational effect |
|---|---|
| BackendService, BackendVm | Catalog, new checkout and order lookup unavailable; client Blob image path independent |
| ClientService, ClientVm | All shop APIs unavailable; cached page can remain visible |
| DnsRecordMissing, DnsRecordWrong, DnsLinkMissing | Client cannot resolve/reach backend: catalog and order operations fail after caching/connection effects expire |
| RouteBlackhole, RouteWrongHop, NsgBackend | Client-to-backend path fails: catalog and order operations fail |
| BlobDns, BlobEndpoint, StorageRbac | Fresh product images unavailable; catalog and checkout can still work |
| VaultDns, VaultEndpoint, VaultRbac | New checkout authorization fails; catalog/images and lookup remain independent; retries of an already saved order can succeed |
| DiskFull | New checkout cannot save its order; do not show false confirmation. Existing order lookup and catalog are read paths |
| BadConfig | Backend shop configuration rejected: catalog/order requests fail |
| AksBadImage, AksCrashLoop, AksReadiness, AksScheduling, AksOom | Web rollout becomes unavailable according to the fault's deployment strategy; cached local HTML does not imply a working AKS application |
| ArmRbac | ARM dependency check fails on `/health`; checkout is not gated on ARM Reader. The shop's ten-check operations badge does not include this ARM check |
| KubeRbac | Operator permission check fails independently; customer shop can remain usable |
| CpuPressure, MemoryPressure | Resource-pressure check fails; shopping may slow down but an outage is not guaranteed |
| TelemetryGap | AMA/heartbeat observation fails or becomes stale; shop remains independent |
| Web scale-to-zero | Shop API calls fail while the local cached page may remain visible |

Photos already loaded cannot be made unseen. The UI refreshes every 30 seconds while visible and when returning to the tab. It removes images on a failed refresh or after their 60-second display lease expires, with no hidden local fallback. DNS caches, existing connections and RBAC propagation affect timing. BlobDns previously did not produce the expected symptom in the old health workload; it was restored and remains unresolved. Do not present it as a verified shop outage.

## Verification Evidence

- 21 Node tests pass, including server-side pricing, idempotency, persistence, Blob/Vault/backend failures, failed order writes, request/concurrency budgets, same-origin checkout enforcement and bounded seed retries.
- Public HTTPS verification passed with normal certificate validation: HTTP redirect, four JPEGs, catalog, checkout and persisted lookup, private-route 404s and cross-origin checkout rejection.
- Public browser: four decoded 480x360 images, $89 watch checkout and lookup, desktop and 390px mobile without horizontal overflow. A visible-tab simulation in the editor's hidden browser received three real Azure media responses over 65 seconds with all images still decoded and no warning; only browser visibility was simulated, not API data.
- Public verification evidence is recorded under ignored `.state/verification/public-shop.json`. Live Blob/Vault public access remains disabled and the AKS API remains private.
- PowerShell parsing, Node syntax, scenario catalog and existing scenario engine checks pass.
- Updated VM Bicep compiles with no diagnostics.
- Local browser: four decoded images, cart, confirmed order and reference lookup, desktop and 390px mobile rendering, no horizontal overflow.
- Browser-routed image failure removes all four images while retaining four catalog products; removing the test route restores all images. This is local UI evidence only.
- Live catalog, four Blob images, simulated checkout and persisted order lookup passed on 2026-09-22.
- Live browser through the private viewer: all four Azure Blob images decoded at 480x360, no horizontal overflow at the mobile viewport, and lookup displayed the persisted $89 Field Watch order. The loopback URL is a private relay, not a locally simulated shop.
- BlobEndpoint: images 503, catalog 200; reset restored images. The initial rejection-based reset exposed an unsupported Azure transition; recovery and the corrected delete/recreate scenario both passed.
- VaultEndpoint: new checkout 503, catalog 200; reset restored checkout and persisted lookup.
- DiskFull: new checkout 503 and attempted order lookup 404; reset restored checkout. No false confirmation or saved order was produced during the fault.
- Final Test-Lab -IncludeTelemetry passed after restoration, including six application checks, VM services/disks/DNS, operator access, agent provisioning and fresh heartbeats from both VMs. Evidence is under ignored `.state/verification/` and `.state/baseline-verification.json`.
- Other shop scenarios and an SRE Agent investigation remain unverified.