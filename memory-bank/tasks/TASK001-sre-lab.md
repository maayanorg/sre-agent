# TASK001 - Azure SRE Lab

**Status:** In Progress
**Added:** 2026-09-15
**Updated:** 2026-09-15

## Original Request
Deploy a reusable, cost-conscious Azure SRE Agent lab for infrastructure admins and DevOps. Cover DNS, UDR, NSG, private endpoints, AKS, VM unavailability, Azure and Kubernetes RBAC, disk full, bad deployment, dependency outage, CPU/memory pressure and missing telemetry. Separate executable scripts for every fault and recovery.

## Implementation Plan
- Deploy only to subscription 15ba7e94-568d-4ba9-bb5d-29ed107ac109, Sweden Central.
- Main RG rg-srelab-swedencentral-001; AKS managed RG rg-srelab-aksnodes-swedencentral-001.
- Build Bicep, PowerShell fault engine, individual entry scripts and runbooks.
- Validate infrastructure, deploy, verify healthy baseline and rehearse faults with restoration.

## Progress Tracking
**Overall Status:** In Progress - 85%

| ID | Description | Status | Updated | Notes |
|---|---|---|---|---|
| 1 | Azure preflight | Completed | 2026-09-15 | Region supported, subscription enabled, quotas available, RG absent |
| 2 | Infrastructure | Completed | 2026-09-15 | Baseline deployment succeeded; AKS Standard_D2s_v4 and SRE Agent Review mode |
| 3 | Scenarios and runbooks | In Progress | 2026-09-15 | All 28 scripts, shared engine, operations dashboard and SCENARIOS.md implemented; live rehearsals underway |
| 4 | Deploy and verify | Completed | 2026-09-15 | Frontend deployed; real browser outage/recovery verified; full baseline including telemetry passed afterward |

## Progress Log
### 2026-09-15
- Verified Microsoft.App/agents API 2026-01-01 is available in Sweden Central.
- Agent uses Review mode, managed identity scoped to lab RG. Service rejected the original ReadOnly setting.
- SRE Agent always-on billing persists while stopped; deletion required to stop all agent charges.
- Retried the deployment with Standard_D2s_v4. Verified the subscription policy blocks Standard_D2s_v5 only; did not modify policy.
- Verified live SRE Agent provisioningState Succeeded and mode Review. Main deployment remains Running with AKS as the only unfinished component.
- PowerShell parsing and Node syntax checks passed. VM health-check wait was cancelled; no healthy baseline claim yet.
- Deployment subsequently succeeded. Both VM bootstraps completed; Kubernetes web/probe deployments rolled out successfully.
- Fixed Windows Azure CLI quoting in the heartbeat query by using KQL single-quoted literals.
- AKS Run Command cannot impersonate the operator service account. The baseline test now obtains a ten-minute service-account token inside Run Command and checks its actual permissions; no token is returned or persisted locally.
- Full Test-Lab.ps1 -IncludeTelemetry passed: VM services/data disks, DNS, Storage/Key Vault/ARM dependencies, Kubernetes connectivity/operator RBAC, agent provisioning and both fresh VM heartbeats.
- Verification evidence is stored in ignored .state/baseline-verification.json. This verifies the healthy baseline, not incident rehearsals or an SRE Agent investigation workflow.
- Added ARCHITECTURE.md and .github/modernize/assessment/engines/facts/architecture-diagram.md with workload/network/identity relationships, two Mermaid diagrams, healthy-demo commands and a planned fault-impact table. Local links, fences and diagram structure passed checks; visual rendering was not tested.
- Clarified that NGINX is independent of VM and Azure data dependencies, the probe stays Running on HTTP failures, and rolling updates may preserve availability. No public app ingress, fault scripts, automatic agent routing or verified investigation workflow is implied by the deployed baseline.
- Subsequently replaced NGINX with a Node.js status frontend showing six real checks, including AKS-to-client/backend paths. Updated architecture and diagrams to reflect this change.
- Kept access private because public exposure was not approved. Start-DemoViewer.ps1 serves the actual cached AKS page on loopback and retrieves real snapshots through AKS Run Command; delayed/stale observations are explicit.
- Rehearsed Set-WebOutage.ps1 Inject and Reset: web pod terminated, browser showed unavailable, saved replicas restored, browser returned to six healthy checks. Final Test-Lab.ps1 -IncludeTelemetry passed. Lab left healthy.
- Added five passing frontend tests to Validate-Local.ps1 and six-check API assertions to Test-Lab.ps1. Desktop/mobile rendering, nonblank history canvas and pause/resume verified through the integrated browser. DEMO.md documents commands and relay limitations.
- Added README.md with all 22 source files grouped by folder, first-time setup, repeatable two-terminal demo order, conditional recovery and frontend update steps. Documented ValidateOnly side effects and Run Command polling limitations. Source coverage, local links and PowerShell examples validated without executing Azure operations.
- Added 28 individual scenario wrappers, state-before-mutation engine, atomic recovery records, exclusive incident/maintenance lock, VM/AKS command mutexes, investigation and verification commands, and sequential finally-protected rehearsal runner.
- Added ten independent operations checks and red operational summary. Browser verified KubeRbac denial and sustained AMA failure while application remains 6/6. Operator auth now isolates kubeconfig credentials; prior token-only check could falsely inherit observer privileges.
- AMA runtime masks were ineffective for its /etc-defined unit. Replaced with dedicated runtime ExecCondition override, verified sustained failure and recovery. Service overrides disappear on reboot and explicit reset removes only the owned file.
- Live inject/recovery verified for KubeRbac, TelemetryGap, BackendService, ClientService, BadConfig, DiskFull, DnsRecordMissing, DnsRecordWrong and DnsLinkMissing. Remaining network, endpoint, Azure RBAC, AKS, power and pressure rehearsals are still underway. Do not claim a final healthy state while a batch is running.
- Fixed UTC verification: ConvertFrom-Json produces DateTime values; reparsing their string representation incorrectly shifted observations by three hours. Cast DateTime preserving Kind instead, with regression check.
- Updated README, DEMO, architecture and SCENARIOS guide for implemented behavior and explicit observer, local-lock, ARM overwrite and unverified SRE Agent workflow limits. Latest top-level operational alert still needs frontend deployment and final browser checks.