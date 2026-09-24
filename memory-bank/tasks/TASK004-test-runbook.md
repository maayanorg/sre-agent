# TASK004 - Ordered Test Runbook

**Status:** Completed
**Added:** 2026-09-22
**Updated:** 2026-09-22

## Original Request
Create a Markdown file with the test use cases in order, following the Blob and Key Vault process, then continuing through all tests with phases and SRE prompts.

## Implementation Plan
- Match the existing scenario catalog, script parameters and documented shop behavior.
- Write five phases per test: baseline, injection, impact, alert/SRE investigation and recovery.
- Include known alert gaps, safe reset rules, evidence criteria and links from the main guides.
- Validate coverage, PowerShell syntax and paths without running Azure faults.

## Progress Tracking
**Overall Status:** Completed - 100%

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 4.1 | Ground procedure in implementation | Completed | 2026-09-22 | Catalog, scenario engine entry point, monitoring rules, public-shop checker and web-outage script inspected |
| 4.2 | Write ordered runbook | Completed | 2026-09-22 | TEST-RUNBOOK.md covers all 28 catalog scenarios plus web scale-to-zero, five phases and a tailored SRE prompt each |
| 4.3 | Validate examples and coverage | Completed | 2026-09-22 | 29 sections, all catalog names, required actions, 66 PowerShell blocks, script paths, links and fences passed static checks |
| 4.4 | Discovery and handoff | Completed | 2026-09-22 | README and SCENARIOS link to the runbook; no Azure mutation or new live rehearsal performed |

## Progress Log
### 2026-09-22
- Kept BlobEndpoint and VaultEndpoint first, followed by DiskFull and progressively broader service, network, AKS and operational faults.
- Included shared preflight/recovery gates, fresh-checkout and idempotency cautions, explicit saved-state reset commands and an evidence checklist.
- Documented current alert limitations: client-hosted probe loss, missing-heartbeat grouping, historical pod rows, unready/zero-replica gaps and no dedicated pressure/RBAC alerts.
- Distinguished native Azure Monitor incident scanning from a generated HTTP-trigger webhook; an agent homepage is not a trigger URL. Automatic SRE reception remains a separate verification criterion, not a claimed success.
- Preserved prior evidence limits, including the inconclusive BlobDns rehearsal. No current incident was injected, reset or otherwise modified.