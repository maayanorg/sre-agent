# TASK008 - Repair Baseline Redeployment

**Status:** Completed
**Added:** 2026-10-29
**Updated:** 2026-10-29

## Original Request
Resolve RouteWrongHop injection failing because the baseline ARM deployment is Failed.

## Findings
- Both VM modules failed with PropertyChangeNotAllowed for immutable osProfile.customData after bootstrap/application source changed.
- Injection correctly refused the failed baseline. No scenario guard was weakened.
- What-if also exposed existing AKS and private-endpoint subnet NSG associations absent from the template. These must be retained, including the public-shop ingress rule.

## Implementation Plan
- Discover existing VM names and omit bootstrap customData only for those VMs.
- Discover and preserve the two existing subnet NSG associations without changing rules.
- Validate, review what-if, redeploy and verify actual deployment success and live health.

## Progress Tracking
**Overall Status:** Completed - 100%

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 8.1 | Diagnose and repair deployment path | Completed | 2026-10-29 | Existing VM bootstrap omitted; subnet NSGs retained |
| 8.2 | Validate and redeploy | Completed | 2026-10-29 | Azure validation passed; what-if showed no VM/subnet changes or resource creation/deletion; real deployment Succeeded |
| 8.3 | Verify and document | Completed | 2026-10-29 | Injection WhatIf, telemetry baseline, local suite and public checkout passed |

## Progress Log
### 2026-10-29
- Applied the full corrected baseline with the maintenance lock. Did not replace VMs, format data disks, or inject a fault.
- Get-Lab succeeded without cached-metadata fallback. RouteWrongHop Inject -WhatIf reached ShouldProcess without mutating routes; this is not a fault rehearsal.
- Test-Lab -IncludeTelemetry passed services, mounts, DNS, six frontend checks, Kubernetes connectivity/RBAC, agent provisioning and telemetry.
- What-if evidence is in ignored .state/redeploy-whatif.json. Reboot resilience remains outside this repair.
- Validate-Local passed all 21 Node tests, PowerShell parsing and catalog/engine/public-shop/metadata checks. Public HTTPS suite passed at 12:02:15Z with four products/images, blocked private routes and cross-origin checkout, and persisted order 066d240b-7ea9-458d-949a-a16d5167e290.
- This successful deployment supersedes the failed-deployment limitation recorded in TASK006 and TASK007; their historical observations remain unchanged.