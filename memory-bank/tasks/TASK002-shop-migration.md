# TASK002 - Real Shop Workload

**Status:** Completed
**Added:** 2026-09-15
**Updated:** 2026-09-22

## Original Request
Migrate the synthetic dashboard to a usable shop whose images and shopping operations actually depend on the deployed Azure resources, so fault scripts demonstrate corresponding customer impact.

## Implementation Plan
- Implement catalog, Blob media, cart, Vault-authorized simulated checkout and persisted order lookup.
- Retain private boundaries and existing scenarios; separate operational failures from customer availability.
- Validate locally, seed private resources, deploy, and rehearse real customer impact and recovery.

## Progress Tracking
**Overall Status:** Completed - 100% for deployment and representative shop failure/recovery; exhaustive rehearsals remain in TASK001.

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 2.1 | Shop services and UI | Completed | 2026-09-15 | Node API, managed-identity Blob/Vault reads, idempotent file-backed orders, responsive storefront |
| 2.2 | Private integration and workflow | Completed | 2026-09-22 | VM seeding, AKS/VM deployment and live private relay verified |
| 2.3 | Local verification | Completed | 2026-09-22 | 19 Node tests, PowerShell/Node parsing, endpoint recovery regression; earlier VM compile and local UI checks |
| 2.4 | Azure data/deployment/rehearsals | Completed | 2026-09-22 | Four Blob images, Vault secret, persisted orders; BlobEndpoint, VaultEndpoint and DiskFull failure/recovery; final telemetry baseline passed |
| 2.5 | Documentation | Completed | 2026-09-22 | SHOP.md and existing guides updated with deployed status, evidence and limits |

## Progress Log
### 2026-09-22
- Restarted the stale local viewer after deployment. Actual Azure shop is accessible at http://127.0.0.1:8091/. Browser decoded all four Blob images and displayed the persisted $89 Field Watch order by reference; mobile viewport had no horizontal overflow. Only one Azure viewer left running to limit Run Command contention.
- User approved temporary Blob container Contributor and vault Secrets Officer grants to the shared VM identity. Seeded inside Azure with managed identity; grants removed and absence verified. Secret values never returned.
- Started stopped VMs and AKS. Updated both VM services and AKS web. Live catalog, all four images, demo checkout and persisted lookup passed.
- Fixed Windows VM command length using --scripts @file, removed incompatible role-list flags, added bounded setup-only RBAC propagation retries, and made the shop relay sentinel independent of newline escaping.
- Initial Blob rejection was not re-approvable. Recovered by recreating the endpoint; changed both endpoint scenarios to capture/delete/recreate with DNS bindings. Corrected Blob and Vault scenarios both passed live. Dynamic endpoint IP/provider connection IDs may change.
- Blob fault: media 503/catalog 200. Vault fault: new checkout 503/catalog 200. Disk fault: checkout 503/order lookup 404. Every reset recovered; checkout and lookup passed afterward.
- Final Test-Lab -IncludeTelemetry passed after the corrected Blob rehearsal. No active incident retained. Remaining scenario rehearsals and SRE Agent investigations stay explicitly unverified under TASK001.

### 2026-09-15
- Kept existing infrastructure and runtime identity permissions. User unavailable to answer access question; did not expose services or transfer credentials through Run Command.
- Laptop resolves storage public address 20.150.44.36, not 10.70.3.x private endpoint. Shop assets downloaded locally but not uploaded; secret not created.
- Preview http://127.0.0.1:8092 explicitly identifies local fixtures. Orders in .state/shop-preview/orders; not Azure evidence.
- Browser confirmed an order and reference lookup. Four images decoded, disappeared under routed 503 and recovered. Desktop/mobile checked; integrated-browser stability waits timed out, direct Playwright clicks/evaluate completed the checks.
- VM Bicep compiled successfully with no diagnostics. Existing viewer accepts both old health root and new shop root to preserve access before migration.
- Catalog is fixed, not stock inventory; payment/fulfillment simulated. No authentication, backup or full power-loss durability. Live relay image-size/latency and all shop fault scenarios unverified.
- Next: run Initialize-ShopData from an authorized private workstation, then Deploy-Shop -DataAlreadySeeded, restart viewer, test real customer actions/faults with saved-state resets and recheck baseline. Do not claim task complete.