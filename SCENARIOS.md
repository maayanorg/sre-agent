# Incident Scenarios

**Shop deployed:** [SHOP.md](SHOP.md) maps every scenario to shopping or operational impact. BlobEndpoint, VaultEndpoint and DiskFull have live shop failure/recovery evidence. Other health-based Verify results are not proof of shopping behavior.

For an ordered rehearsal with five phases and a scenario-specific SRE prompt for every test, use [TEST-RUNBOOK.md](TEST-RUNBOOK.md). It also distinguishes expected automatic alerts from known detection gaps.

There are 28 additional scenarios plus the existing web scale-to-zero outage. Each scenario has its own entry script, saved-state reset, status/investigation action and evidence verification. They affect only the existing SRE lab. No extra always-on Azure resource is required.

## Execution Order

Run from the workspace root in PowerShell 7. Keep the private viewer open in a separate terminal. Start it while the web application is healthy.

```powershell
./tests/Validate-Local.ps1
./scripts/Test-Lab.ps1 -IncludeTelemetry
./scripts/Start-DemoViewer.ps1 -Port 8091
```

In the second terminal, choose one scenario. Every script below accepts the same four actions:

```powershell
./scripts/scenarios/KubeRbac.ps1 -Action Inject -WhatIf
./scripts/scenarios/KubeRbac.ps1 -Action Inject
./scripts/scenarios/KubeRbac.ps1 -Action Status
./scripts/scenarios/KubeRbac.ps1 -Action Verify
./scripts/scenarios/KubeRbac.ps1 -Action Reset
./scripts/scenarios/KubeRbac.ps1 -Action Verify -Expected Recovered
```

`Status` includes read-only investigation evidence. `Verify` requires an actual failed request or operational check; writing an injection record is not evidence. DNS caches, routes, private endpoint approval and Azure RBAC can take time to propagate. Retry Verify rather than injecting again. RBAC can take many minutes, and inherited assignments can prevent an intended denial.

`Reset` restores captured state and verifies recovery before deleting the active record. If verification fails, the record remains. A subsequent Reset retries verification without repeating a completed restore. Do not delete recovery state or redeploy the baseline to hide an unresolved incident.

## Scenario Catalog

Paths below are individual executable entry scripts. Application checks may show secondary failures when a client dependency fails or a synchronous Azure request holds up the client process.

| Script | Injected fault | Customer-visible evidence / investigation |
|---|---|---|
| [DnsRecordMissing](scripts/scenarios/DnsRecordMissing.ps1) | Remove captured backend A record | Backend/client HTTP fail; private DNS record absent |
| [DnsRecordWrong](scripts/scenarios/DnsRecordWrong.ps1) | Point backend A record at unused 10.70.2.250 | Backend/client HTTP fail; wrong A value |
| [DnsLinkMissing](scripts/scenarios/DnsLinkMissing.ps1) | Remove application zone link to services VNet | Client cannot resolve dependency; AKS backend may remain healthy |
| [RouteBlackhole](scripts/scenarios/RouteBlackhole.ps1) | Add client /32 route with next hop None | Client fails; direct AKS backend request can remain healthy |
| [RouteWrongHop](scripts/scenarios/RouteWrongHop.ps1) | Add client /32 route to unused virtual appliance | Client fails; route points to 10.70.1.250 |
| [NsgBackend](scripts/scenarios/NsgBackend.ps1) | Temporarily replace captured AllowLabHttp rule with backend-port deny | Backend/client fail; NSG deny on 8081 |
| [BlobDns](scripts/scenarios/BlobDns.ps1) | Remove Blob private DNS services link | Storage request fails; private DNS link absent |
| [VaultDns](scripts/scenarios/VaultDns.ps1) | Remove Vault private DNS services link | Vault request fails; private DNS link absent |
| [BlobEndpoint](scripts/scenarios/BlobEndpoint.ps1) | Capture/delete Blob endpoint; recreate endpoint and DNS binding on reset | Storage/images fail; endpoint absent |
| [VaultEndpoint](scripts/scenarios/VaultEndpoint.ps1) | Capture/delete Vault endpoint; recreate endpoint and DNS binding on reset | Vault/new checkout fail; endpoint absent |
| [StorageRbac](scripts/scenarios/StorageRbac.ps1) | Remove only VM identity's captured Blob reader assignment | Storage authorization fails after propagation |
| [VaultRbac](scripts/scenarios/VaultRbac.ps1) | Remove only VM identity's captured Secrets User assignment | Vault authorization fails after propagation |
| [ArmRbac](scripts/scenarios/ArmRbac.ps1) | Remove only VM identity's captured RG Reader assignment | ARM authorization fails after propagation |
| [KubeRbac](scripts/scenarios/KubeRbac.ps1) | Empty operator RoleBinding subjects, preserving UID | Operator access red; application can stay fully healthy |
| [BackendService](scripts/scenarios/BackendService.ps1) | Runtime startup-condition override and stop backend app service | Backend/client fail; systemd service inactive |
| [ClientService](scripts/scenarios/ClientService.ps1) | Runtime startup-condition override and stop client app service | Client/storage/vault/ARM fail; backend can remain healthy |
| [BackendVm](scripts/scenarios/BackendVm.ps1) | Deallocate backend VM | VM power red, backend/client fail; reset starts same VM |
| [ClientVm](scripts/scenarios/ClientVm.ps1) | Deallocate client VM | VM power red, client-side dependencies fail |
| [AksBadImage](scripts/scenarios/AksBadImage.ps1) | Replace web image with nonexistent tag | Web unavailable; ErrImagePull/ImagePullBackOff events |
| [AksCrashLoop](scripts/scenarios/AksCrashLoop.ps1) | Make web process exit 42 | Web unavailable; terminated/restarting container |
| [AksReadiness](scripts/scenarios/AksReadiness.ps1) | Point readiness probe to absent path | Web unavailable; pod Running but not Ready |
| [AksScheduling](scripts/scenarios/AksScheduling.ps1) | Add unsatisfiable node selector | Web unavailable; Pending/FailedScheduling |
| [AksOom](scripts/scenarios/AksOom.ps1) | Allocate memory beyond existing container limit | Web unavailable; OOMKilled evidence after allocation |
| [DiskFull](scripts/scenarios/DiskFull.ps1) | Fill only dedicated 128 MiB backend lab filesystem | Data disk red; fresh-allocation health check fails |
| [BadConfig](scripts/scenarios/BadConfig.ps1) | Change backend release setting to invalid value | Backend/client fail; config validation error in journal |
| [CpuPressure](scripts/scenarios/CpuPressure.ps1) | One bounded stress worker, 90% CPU quota | Backend CPU red at measured 75% busy; app may stay healthy |
| [MemoryPressure](scripts/scenarios/MemoryPressure.ps1) | Bounded 256 MiB stress allocation | Memory red at measured stress working set >=128 MiB; app may stay healthy |
| [TelemetryGap](scripts/scenarios/TelemetryGap.ps1) | Runtime startup-condition override and stop backend AMA | Monitoring service red promptly; backend heartbeat red after 10 minutes |

The five AKS deployment faults temporarily use `Recreate` so an old healthy replica does not hide the broken replacement. Reset restores the entire captured deployment spec, including the original rollout strategy. The namespace operator role is separate from the privileged Run Command observer.

The existing [Set-WebOutage](scripts/Set-WebOutage.ps1) remains available with Inject, Status and Reset. It shares the same incident lock and cannot overlap a catalog scenario.

## Dashboard Evidence

The six application requests retain their own availability summary. The independent operations section contains ten checks: web deployment, operator authorization, both VM power states, backend CPU/memory/data disk, AMA service, and both expected VM heartbeats.

Operational checks carry individual timestamps and become unknown after three minutes. Missing observer permissions or a failed collection is unknown, not proof of an application outage. A successful Log Analytics query with no heartbeat for an expected host is a telemetry failure, not unknown. The query explicitly includes both expected hosts, including one entirely absent from the result history.

The memory scenario demonstrates resource consumption rather than risking host OOM: red means >=85% host use OR >=128 MiB measured in the bounded stress service. CPU red means >=75% measured busy. Stress expires within ten minutes and is limited to 384 MiB / 90% CPU; explicit Reset is still required to clear the recovery record. Runtime service overrides disappear on reboot, so reboot may also end those symptoms before Reset. Reset removes only the reserved `90-srelab-incident.conf` override and starts the originally active service.

The operations API is served by the local viewer, not by granting the AKS web pod Azure permissions. Operator tokens remain inside the Run Command pod, use an isolated kubeconfig and the cluster CA, and are never returned to the browser. Direct access to the web Service without the viewer shows operational checks as unknown.

## Recovery Safety

- Exactly one recorded incident at a time in this workspace. All scenario mutations and baseline-changing scripts use the same exclusive file lock.
- A six-check healthy application baseline is required before injection; each mutation also checks its own target prerequisites.
- Original DNS/link/rule/role/approval/config/deployment state is captured before mutation. Incident routes require the reserved name to be absent. Kubernetes restoration checks the original object UID.
- State files are atomically replaced. Completed recovery is archived under ignored `.state/history`; observed failure/recovery snapshots are under `.state/verification`.
- Use one operator and one workspace copy. The lock is local, not a distributed lease. Do not modify the same Azure resources manually during a scenario; ARM restore intentionally writes the captured configuration and does not perform a three-way merge.
- Deallocation uses ARM recovery, so a guest Run Command is not needed to restart a VM. Disk fill never targets the OS disk, and stress never runs on the AKS node.
- Keep `.state` private and intact. It contains resource configuration and recovery details, not browser credentials.

## Batch Rehearsal

This is an actual destructive-to-availability rehearsal, not a dry run. It executes sequentially, verifies the symptom, and attempts restoration in `finally`. It stops on an unresolved fault and retains recovery state. Retry counts are bounded; Azure propagation can outlast them.

```powershell
./scripts/Rehearse-Scenarios.ps1 -Scenario DnsRecordWrong,RouteBlackhole,NsgBackend,DiskFull
```

Do not run this while presenting a different incident. The viewer is read-only and remains independent. Local VM and AKS command mutexes serialize requests from viewer/verification/fault scripts, which can increase observation delay.

## Azure SRE Agent Investigation

Open the deployed Review-mode SRE Agent and provide a bounded request such as:

> Investigate this lab incident in rg-srelab-swedencentral-001 only. The affected check is [check], first observed at [UTC timestamp]. Compare recent resource changes, dependency paths, deployment status and available telemetry. Separate observed evidence from hypotheses. Propose a diagnosis and recovery plan, but do not execute changes.

Use Status evidence and the dashboard timestamps to challenge the diagnosis. For permissions, distinguish the observer's identity from the workload/operator identity. For telemetry, ask whether absent logs mean absent requests or broken collection. Perform recovery using the scenario Reset command after review.

The agent currently has scoped read permissions. Automatic alert routing, a tested investigation connector/workflow, guest commands and remediation are not implied by this guide. Do not broaden its privileges just to make a demonstration appear successful.

## Deployment Updates

For this feature update, run these only with no active incident:

```powershell
./scripts/Update-VmWorkload.ps1
./scripts/Deploy-Frontend.ps1
./scripts/Test-Lab.ps1 -IncludeTelemetry
```

Restart an optional operator viewer to load updated HTML and local relay code. The public shop now uses a separate HTTPS gateway and does not require that relay; see [SHOP.md](SHOP.md). Operations routes and fault controls remain private. AKS Run Command polling remains an event-lab workaround for the private dashboard, not a production access pattern.

## Verification Record

Implementation and local tests are not equivalent to live rehearsal. The authoritative per-scenario live records are `.state/verification/<Scenario>-Injected.json`, `<Scenario>-Recovered.json`, and the corresponding archived recovery record. A recovered-only record means restoration was verified, not necessarily that the intended failure was demonstrated. Browser screenshots are separate evidence for presentation behavior.