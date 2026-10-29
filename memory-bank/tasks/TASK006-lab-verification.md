# TASK006 - Lab Verification After Failed Redeployment

**Status:** Completed
**Added:** 2026-10-29
**Updated:** 2026-10-29

## Original Request
Fix `./scripts/Test-Lab.ps1 -IncludeTelemetry`.

## Findings
- The command stopped in Get-Lab before health or telemetry checks. Today's srelab-baseline deployment was Failed with null outputs.
- Both nested VM deployments failed with PropertyChangeNotAllowed for osProfile.customData. Existing VMs cannot accept modified bootstrap custom data.
- The saved .state/lab.json still describes the existing lab. Deployment history and live workload health are separate facts.

## Implementation Plan
- Add explicit cached-metadata recovery for the live baseline test only.
- Validate subscription, resource group, resource ID scope and live workspace customer ID; preserve default deployment guards.
- Cover recovery and rejection cases locally, then rerun the exact live command.

## Progress Tracking
**Overall Status:** Completed - 100%

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 6.1 | Diagnose initial failure | Completed | 2026-10-29 | Failed deployment and immutable VM customData errors confirmed |
| 6.2 | Implement scoped recovery | Completed | 2026-10-29 | Get-Lab opt-in; only Test-Lab opts in; explicit warning retained |
| 6.3 | Verify fix | Completed | 2026-10-29 | Focused regression tests and exact live command passed |

## Progress Log
### 2026-10-29
- Successful deployments still use live outputs. Failed or canceled deployments can use a scoped cache only when explicitly requested; running deployments and missing caches remain blocked.
- Verified default rejection, successful output path, warning emission, missing cache, running deployment, wrong subscription, out-of-scope resource and mismatched live workspace customer ID.
- Exact Test-Lab command passed VM service/disk/DNS checks, six frontend checks, Kubernetes connectivity/operator permissions, SRE Agent provisioning and fresh telemetry from both VMs.
- No Azure configuration or infrastructure was changed. The ARM deployment still reports Failed; its immutable-customData redeployment issue was not repaired or represented as a successful deployment.
- Added the regression script to Validate-Local.ps1. Live evidence is recorded in ignored .state/baseline-verification.json.