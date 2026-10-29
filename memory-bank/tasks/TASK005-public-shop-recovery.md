# TASK005 - Public Shop Recovery

**Status:** Completed
**Added:** 2026-10-29
**Updated:** 2026-10-29

## Original Request
Fix the failure from `./scripts/Test-PublicShop.ps1 -IncludeCheckout`.

## Findings
- The public gateway responded, but the client VM had no port 8080 listener. Its service was inactive and `/mnt/srelab-data` was missing.
- The existing `/opt/srelab/data.img`, application files and fstab entry were intact. Cloud-init reported a mount failure after startup; `/mnt` is the Azure temporary disk.
- After restoring the client mount and starting the service, backend DNS initially failed while direct-IP catalog access returned HTTP 200. The Azure A record and VNet links were correct. Subsequent local and direct Azure DNS queries resolved correctly without a DNS configuration change.

## Implementation Plan
- Diagnose the private client and backend paths.
- Restore the existing client data mount and service under the maintenance lock, without formatting or replacing data.
- Rerun the exact failing public test with checkout.

## Progress Tracking
**Overall Status:** Completed - 100%

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 5.1 | Diagnose catalog failure | Completed | 2026-10-29 | Missing client mount point and inactive service confirmed |
| 5.2 | Restore client service | Completed | 2026-10-29 | Recreated mount directory, mounted existing image, started srelab |
| 5.3 | Verify public checkout | Completed | 2026-10-29 | Full public test passed at 08:32:20Z |

## Progress Log
### 2026-10-29
- Verified the original lab subscription and tags; no active incident or web-outage recovery record blocked maintenance.
- Mounted the existing client image and started the service. No application, DNS, access-control or infrastructure source changes were needed for this recovery.
- `Test-PublicShop.ps1 -IncludeCheckout` passed: valid HTTPS, HTTP redirect, four products and JPEG images, private-route blocks, cross-origin rejection, checkout and persisted lookup.
- Verified order reference: `14f08be8-4ccc-4754-bb4e-4535f8d12441`.
- Scope limit: reboot resilience and a complete lab/telemetry baseline were not tested. The mount remains under `/mnt`; this recovery does not claim a permanent boot-order fix.