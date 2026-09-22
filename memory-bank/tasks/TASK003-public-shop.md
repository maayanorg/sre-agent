# TASK003 - Public HTTPS Shop

**Status:** Completed
**Added:** 2026-09-22
**Updated:** 2026-09-22

## Original Request
Images are unavailable; make the shop a public site, not localhost.

## Implementation Plan
- Refresh images before the 60-second lease and when a tab becomes visible.
- Expose only storefront and shop APIs through a public AKS HTTPS gateway.
- Keep storage, vault, VMs, control plane and operations routes private.
- Validate HTTPS, images, checkout and responsive browser rendering at the public URL.

## Progress Tracking
**Overall Status:** Completed - 100%

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 3.1 | Refresh and request safety | Completed | 2026-09-22 | 30-second refresh/visibility handler; request/checkout/concurrency budgets; deployed frontend |
| 3.2 | Public HTTPS gateway | Completed | 2026-09-22 | Caddy validated; LoadBalancer and scoped subnet NSG rule deployed; trusted ACME certificate |
| 3.3 | Public verification | Completed | 2026-09-22 | HTTPS, redirect, four images, persisted checkout, private routes, desktop/mobile and 65-second refresh check passed |
| 3.4 | Documentation | Completed | 2026-09-22 | Public URL, lifecycle commands, private boundary, costs and evidence documented |

## Progress Log
### 2026-09-22
- User explicitly authorized a public site. Chose separate Caddy LoadBalancer endpoint, Azure DNS label and ACME HTTPS, with certificate PVC and non-root/read-only gateway.
- No public Blob/Vault access or changes to private AKS API. Public routes limited to root and shop APIs; anonymous demo only, not production commerce.
- Local 21 Node tests and PowerShell scenario/public manifest checks passed. Updated frontend rolled out. Stopped the old localhost viewer.
- Gateway configuration is validated in an unexposed pod before creating the public Service. External tests pending deployment.
- Resolved Caddy startup by adding only NET_BIND_SERVICE to the dropped-capabilities set while retaining non-root/read-only/no-escalation settings. Real Caddy validation then passed.
- Public connection timeout was caused by an additional subnet NSG with no Internet allow rule. Deployment now discovers this NSG and manages only an owned rule restricted to the shop public IP and TCP 80/443; Remove deletes that rule. AKS-managed node rules are untouched.
- Public URL: https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com/ . Trusted HTTPS, HTTP redirect, four JPEGs, private-route 404s, cross-origin checkout rejection and persisted order lookup passed. Evidence saved in .state/verification/public-shop.json.
- Browser verified four 480x360 images, $89 watch order/lookup, desktop/mobile with no overflow. Editor browser reports hidden; visible-tab simulation received three real media responses over 65 seconds with images retained and no warning. No API responses were mocked.
- Verified Blob/Vault public access disabled and private AKS API retained. Gateway adds public IP/load-balancer and certificate disk costs; demo remains anonymous/simulated, not production commerce. All-28 scenario and SRE Agent verification remain outside this completed task.