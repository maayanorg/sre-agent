# SRE Day: Ordered Test Runbook

Use this runbook to repeat the Blob and Key Vault demonstrations, then work through the remaining lab scenarios with the same phases: healthy baseline, injection, observed impact, alert and SRE investigation, and recovery.

**Run from the workspace root in PowerShell 7. Execute one phase at a time, not an entire test as one pasted command block.** Injection commands intentionally interrupt availability. This document does not execute them.

**Public shop:** https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com/

**Scope:** subscription `15ba7e94-568d-4ba9-bb5d-29ed107ac109`, resource group `rg-srelab-swedencentral-001`, Sweden Central. AKS-managed resources are in `rg-srelab-aksnodes-swedencentral-001`; the SRE Agent's configured managed-resource scope does not automatically include that group.

See [SHOP.md](SHOP.md) for the workload, [SCENARIOS.md](SCENARIOS.md) for engine and recovery details, and [README.md](README.md) for deployment prerequisites.

## Evidence And Safety

- BlobEndpoint, VaultEndpoint and DiskFull have prior live shop failure/recovery evidence. Do not treat the other expected results below as completed shop rehearsals.
- A successful `Inject` means a mutation completed. `Verify` checks the scenario's health or operational symptom, not necessarily a customer purchase. Demonstrate the customer operation separately.
- Use exactly one recorded incident, one operator and one workspace copy at a time. Do not manually alter the target, redeploy the baseline, or run another fault while recovery state exists.
- Preserve the ignored `.state` directory. It contains captured recovery configuration. Do not publish it or delete it to bypass an incident lock.
- If propagation delays cause `Verify` to fail, inspect `Status`, then retry `Verify`; do not reinject. Unknown or stale observations are not proof of an outage.
- If `Reset` restores the resource but recovery verification fails, preserve state and retry the same `Reset` after inspecting the remaining failure. Do not move to the next test.
- Reset is operator-controlled in this rehearsal. Ask SRE to investigate and propose recovery, not to modify resources. Concurrent agent changes could conflict with captured-state restoration.
- Browser state and existing connections can mask failures. Use fresh requests, record UTC timestamps, and distinguish cached content from successful backend operations.
- Never expose secrets, tokens, connection strings, or generated webhook URLs in prompts or evidence.

## Recommended Order

The first three tests isolate different dependencies behind a working storefront. Later tests broaden the blast radius, then finish with operational failures that need not cause customer outages.

| Test | Scenario | Demonstration | Alert expectation |
|---|---|---|---|
| 01 | BlobEndpoint | Images fail; browsing survives | Dependency |
| 02 | VaultEndpoint | New checkout fails; images survive | Dependency |
| 03 | DiskFull | New order cannot be persisted | Dependency |
| 04 | BackendService | Backend application stopped | Dependency |
| 05 | ClientService | Shop's client service stopped | Dependency, if probe runs |
| 06 | BadConfig | Running process with invalid configuration | Dependency |
| 07 | DnsRecordMissing | Backend name has no A record | Dependency |
| 08 | DnsRecordWrong | Backend name resolves incorrectly | Dependency |
| 09 | DnsLinkMissing | Services VNet loses application DNS | Dependency |
| 10 | RouteBlackhole | Client-to-backend traffic discarded | Dependency |
| 11 | RouteWrongHop | Client-to-backend traffic misrouted | Dependency |
| 12 | NsgBackend | Backend port blocked by NSG | Dependency |
| 13 | StorageRbac | Image access denied by authorization | Dependency, after propagation |
| 14 | VaultRbac | Checkout secret access denied | Dependency, after propagation |
| 15 | BlobDns | Blob private DNS path broken | Conditional; known rehearsal gap |
| 16 | VaultDns | Vault private DNS path broken | Dependency if request fails |
| 17 | BackendVm | Backend compute deallocated | Dependency; heartbeat alert conditional |
| 18 | ClientVm | Client compute and probe unavailable | No reliable outage alert |
| 19 | AksBadImage | Web image cannot be pulled | Pod |
| 20 | AksCrashLoop | Web process repeatedly exits | Pod |
| 21 | AksReadiness | Running web pod cannot serve traffic | No reliable readiness alert |
| 22 | AksScheduling | Web pod cannot find an eligible node | Pod |
| 23 | AksOom | Web container exceeds memory limit | Pod, if evidence is ingested |
| 24 | Web scale-to-zero | Web deployment has no replicas | No reliable zero-replica alert |
| 25 | ArmRbac | Workload loses management-plane Reader | Dependency; shop can stay healthy |
| 26 | KubeRbac | Operator loses Kubernetes permission | No dedicated alert |
| 27 | CpuPressure | Bounded backend CPU pressure | No dedicated pressure alert |
| 28 | MemoryPressure | Bounded backend memory pressure | No dedicated pressure alert |
| 29 | TelemetryGap | Backend monitoring agent stopped | Missing-telemetry alert unreliable |

## Before The Session

Confirm Azure CLI is already signed in with the authorized lab account. These scripts pin their Azure scope; changing the CLI default subscription does not retarget the lab.

Inspect saved incidents before running any new injection:

```powershell
./scripts/scenarios/BlobEndpoint.ps1 -Action Status
./scripts/Set-WebOutage.ps1 -Action Status
```

The first command reports `activeScenario` even when the saved scenario is not BlobEndpoint. Reset the script matching that active scenario, not whichever test is next. For a saved web outage, use `Set-WebOutage.ps1 -Action Reset`. Do not run Reset when there is no matching recovery record.

Validate the session baseline:

```powershell
./tests/Validate-Local.ps1
./scripts/Test-Lab.ps1 -IncludeTelemetry
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

The last command creates one persisted simulated order and verifies lookup. It does not charge a real payment. Save the returned `orderId` to demonstrate lookup of a pre-existing order during a fault.

The customer demonstration uses the public shop, not localhost. For private operator health and operations evidence, optionally run one viewer in a separate terminal:

```powershell
./scripts/Start-DemoViewer.ps1 -Port 8091
```

Open `http://127.0.0.1:8091/health` only for operator diagnostics. Reuse an existing viewer rather than starting a second one. Collection uses management commands and can take time; observe timestamps and do not confuse Unknown with Failed.

## Alert And SRE Setup

Use the native Azure Monitor incident platform on `sre-srelab-swc-001` with an enabled response plan that matches Sev2 / Warning. One shared plan can cover the lab's three alert rules. Check title and service filters; avoid overlapping quickstart and custom plans. Use Review mode for this rehearsal.

The native integration scans alerts; it does not require a webhook pointing at the agent homepage. The base agent URL is not an HTTP trigger endpoint. A separately configured HTTP trigger needs its generated trigger URL. An Azure Monitor history entry saying an action group executed does not prove SRE accepted an incident.

At the 2026-09-22 investigation, Azure Monitor was selected and the agent identity had Monitoring Contributor at subscription scope. Response-plan matching and automatic investigation were not verified by those checks. Recheck actual behavior during each rehearsal rather than assuming the setup is complete.

| Short name | Azure alert rule | Current detection |
|---|---|---|
| Dependency | `alert-srelab-dependency-failure` | Client `srelab-probe` Syslog has `SRELAB` and a status other than 200 |
| Pod | `alert-srelab-pod-failure` | Ingested `KubePodInventory` has non-Running/non-Succeeded status or selected failure reasons |
| Telemetry | `alert-srelab-telemetry-missing` | Heartbeat rows in the window show last seen older than five minutes |

All three rules are Sev2, evaluate every five minutes, and query a 15-minute window. Ingestion and evaluation add delay; there is no exact firing-time guarantee.

**Separate the alert lifecycles.** Before another test relying on the same rule, wait for the previous alert's monitor condition to become **Resolved**. Manually closing its user-response state is not equivalent. Old failing rows must leave the query window, followed by automatic-resolution evaluations. Starting another dependency fault while the rule is still Fired can produce no new Fired transition.

The SRE integration can merge recurring alerts from the same rule into an existing incident thread. Check incident linkage and timestamps, not just whether a new chat appeared. A manually started chat is useful diagnostic evidence but is not proof of an automatic trigger.

Current detection limits:

- No dedicated public HTTP, checkout, image, CPU, memory, disk-capacity, operator-RBAC, readiness or zero-replica alert exists.
- The dependency probe runs on the client VM. If that VM is off, absence of failure logs is not evidence of health.
- The telemetry alert does not synthesize missing computers. When all heartbeat rows for a host leave its 15-minute window, that host disappears from the result. This can miss a sustained outage or resolve while collection is still broken.
- The pod rule evaluates historical rows, not the latest state per pod. It can remain Fired after recovery; a Running-but-unready pod need not match.
- Missing logs can also reflect ingestion delay or the workspace's configured daily cap. Check collection before blaming the response plan.
- Alert-action wiring was added in Azure, not in the current monitoring template. Do not redeploy monitoring during these tests and assume that wiring will be preserved.

## Five Phases For Every Test

### Phase 1: Healthy Baseline

Finish the previous reset and confirm no active saved incident. Wait for any relevant previous alert to resolve. Run:

```powershell
./scripts/Test-Lab.ps1 -IncludeTelemetry
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Record the test name, UTC start time, baseline order reference and relevant initial resource state. All six application checks must be healthy before catalog-scenario injection. Each test below adds a specific baseline observation.

### Phase 2: Inject And Verify

Run the scenario's Inject, then Verify, then Status commands shown below. Use `-WhatIf` on Inject beforehand when presenting the intended operation. Verify is evidence-based; an inconclusive result requires investigation, not repeated injection.

### Phase 3: Demonstrate Impact

Perform the listed fresh customer operation and capture its result. `Test-PublicShop.ps1` without `-IncludeCheckout` checks browsing, media and boundary behavior, not successful checkout. With `-IncludeCheckout`, it generates a fresh order reference, but it stops at the first failure: an image failure can prevent it from reaching checkout.

Use the browser to test individual operations when the full suite stops early. Do not clear browser checkout state during an ambiguous request; retry its retained reference to determine whether it was already saved. A retry of a confirmed order can succeed without a new secret read or disk write, so it cannot prove a new checkout is healthy.

For focused read-only public probes, set these variables once in the operator terminal:

```powershell
$shop = 'https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com'
Invoke-WebRequest "$shop/api/shop/catalog" -SkipHttpErrorCheck -TimeoutSec 45 |
    Select-Object StatusCode
Invoke-WebRequest "$shop/api/shop/media" -SkipHttpErrorCheck -TimeoutSec 45 |
    Select-Object StatusCode
```

For an order created before injection, substitute its returned ID; do not generate a random ID and expect lookup to succeed:

```powershell
$knownOrderId = '<baseline orderId>'
Invoke-WebRequest "$shop/api/shop/orders/$knownOrderId" -SkipHttpErrorCheck -TimeoutSec 45 |
    Select-Object StatusCode
```

### Phase 4: Alert And SRE Investigation

Record the alert instance, Fired time, rule name and affected resource. Log alerts here target the workspace; SRE must use evidence to identify the affected workload dependency. Check the incident-linked SRE thread and response plan. If no alert is expected, explicitly record the monitoring gap and start a manual investigation instead.

Prepend this boundary to every scenario-specific prompt below, replacing the timestamp:

> Investigate the SRE lab in rg-srelab-swedencentral-001 from [UTC injection time] onward. Work read-only: do not modify resources, restart services, change permissions, or execute recovery. Correlate current observations with recent changes and available logs. Distinguish evidence from hypotheses and call out missing access or telemetry. Identify the affected dependency and propose the smallest recovery plus validation steps. Do not retrieve or display secret values.

Then append the test's **SRE prompt**. These prompts describe symptoms without immediately revealing the injected cause. Ask follow-ups only after the agent presents its initial diagnosis:

> Which evidence distinguishes your root cause from the closest alternative? Which observations would disprove it? What remains unknown?

### Phase 5: Restore And Prove Recovery

Run the test's Reset and recovered Verify commands, then the public-shop suite. The web scale-to-zero script has no Verify action; use its separate procedure in Test 24. Recheck the lab after recovery:

```powershell
./scripts/Test-Lab.ps1 -IncludeTelemetry
```

Capture successful fresh requests and order lookup. Allow heartbeat and alert history to catch up. Record application recovery separately from alert resolution and SRE status synchronization. Finish the evidence checklist at the end before proceeding.

## 01. BlobEndpoint: Product Images Unavailable

**Phase 1:** Complete the shared baseline. Show four decoded product images and a working catalog. This is the first test demonstrated in the session.

**Phase 2:** Capture and delete the Blob private endpoint; data is retained.

```powershell
./scripts/scenarios/BlobEndpoint.ps1 -Action Inject
./scripts/scenarios/BlobEndpoint.ps1 -Action Verify
./scripts/scenarios/BlobEndpoint.ps1 -Action Status
```

**Phase 3:** Keep the public shop visible. Image refresh runs about every 30 seconds while visible; images are removed on failed refresh or after their 60-second display lease. Fresh media requests should fail; catalog and new checkout can still work. Prior rehearsal observed media 503 and catalog 200. Test checkout independently in the browser because the full suite stops at media failure.

**Phase 4:** Expect Dependency from failed `storage` probes. SRE prompt:

> Product images stopped loading, but the catalog is available and order operations can still work. Trace the image retrieval path and compare network reachability, private DNS, endpoint state, and identity authorization. Explain why this dependency failure does not necessarily block checkout.

**Phase 5:** Reset recreates the endpoint and DNS binding; IP and provider-generated IDs may change.

```powershell
./scripts/scenarios/BlobEndpoint.ps1 -Action Reset
./scripts/scenarios/BlobEndpoint.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Show all four images again and complete the shared recovery checks. Wait for Dependency to resolve before Test 02.

## 02. VaultEndpoint: New Checkout Fails

**Phase 1:** Complete the shared baseline and save an existing order reference. Ensure the Blob alert has resolved. This is the second test introduced in the session; verify recovery before continuing to Test 03.

**Phase 2:** Capture and delete the Vault private endpoint; the vault and secret remain.

```powershell
./scripts/scenarios/VaultEndpoint.ps1 -Action Inject
./scripts/scenarios/VaultEndpoint.ps1 -Action Verify
./scripts/scenarios/VaultEndpoint.ps1 -Action Status
```

**Phase 3:** Browse products and images, then attempt a new checkout. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout`: a checkout error is expected, previously observed as 503. Existing order lookup should remain available. A retry of an already saved order may succeed without reading Key Vault, so use a fresh order to prove the fault.

**Phase 4:** Expect Dependency from failed `vault` probes. SRE prompt:

> The catalog and images load, but new checkout fails without an order confirmation. Previously saved orders remain readable. Trace checkout authorization, distinguish a secret-access failure from an order-storage failure, and compare private connectivity with identity authorization. Do not read or expose secret values.

**Phase 5:** Recreate the captured endpoint and DNS binding.

```powershell
./scripts/scenarios/VaultEndpoint.ps1 -Action Reset
./scripts/scenarios/VaultEndpoint.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Prove a fresh order and its lookup succeed; complete shared recovery and wait for Dependency resolution.

## 03. DiskFull: Order Persistence Fails

**Phase 1:** Complete the shared baseline. Save a known order reference and observe free space on the dedicated backend data filesystem.

**Phase 2:** Fill only the dedicated 128 MiB lab filesystem, not the OS disk.

```powershell
./scripts/scenarios/DiskFull.ps1 -Action Inject
./scripts/scenarios/DiskFull.ps1 -Action Verify
./scripts/scenarios/DiskFull.ps1 -Action Status
```

**Phase 3:** Catalog, images and existing-order lookup should work; a fresh checkout must not report success when persistence fails. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout` and expect an error. Prior rehearsal observed checkout 503 and lookup 404 for the unsaved attempt. Capture the attempted browser request ID before testing its lookup; never confuse it with the baseline order.

**Phase 4:** Expect Dependency from failed health writes, not a dedicated disk alert. SRE prompt:

> New checkout fails while catalog and existing orders remain readable. Compare authorization success with the backend's order-write path. Identify the affected filesystem, its available capacity, and whether the failed attempt produced any persisted order. Explain the difference between this incident and the previous checkout failure.

**Phase 5:** Remove the scenario's fill file using saved-state reset.

```powershell
./scripts/scenarios/DiskFull.ps1 -Action Reset
./scripts/scenarios/DiskFull.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Verify capacity, fresh persistence and old-order lookup; complete shared recovery.

## 04. BackendService: Application Service Stopped

**Phase 1:** Complete the shared baseline; distinguish backend VM power from application-service state.

**Phase 2:** Apply the temporary startup-condition override and stop the backend service.

```powershell
./scripts/scenarios/BackendService.ps1 -Action Inject
./scripts/scenarios/BackendService.ps1 -Action Verify
./scripts/scenarios/BackendService.ps1 -Action Status
```

**Phase 3:** Fresh catalog, checkout and order lookup should fail. The client Blob path is independent; use the media probe to check it separately. A reachable VM does not prove the backend application is running.

**Phase 4:** Expect Dependency from health failures. SRE prompt:

> Catalog and order operations fail while the image dependency may still respond. Determine whether the backend VM, network path, or application service is unavailable. Correlate service state, listener health, and available logs; identify any startup condition preventing recovery.

**Phase 5:** Restore the original service state and remove the owned override.

```powershell
./scripts/scenarios/BackendService.ps1 -Action Reset
./scripts/scenarios/BackendService.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm backend availability and complete shared recovery.

## 05. ClientService: Shop API Gateway Service Stopped

**Phase 1:** Complete the shared baseline. Identify the client service separately from the backend and AKS web frontend.

**Phase 2:** Stop the client application with the temporary startup-condition override.

```powershell
./scripts/scenarios/ClientService.ps1 -Action Inject
./scripts/scenarios/ClientService.ps1 -Action Verify
./scripts/scenarios/ClientService.ps1 -Action Status
```

**Phase 3:** All customer shop APIs should fail, including images. Static or cached storefront HTML can remain visible. Direct backend health can remain good.

**Phase 4:** Expect Dependency if the independent client probe timer continues running and logging failed localhost calls. SRE prompt:

> The storefront shell is visible, but catalog, images and order requests fail together. Direct backend health may still be good. Locate the shared failing hop and distinguish a stopped client application from a backend outage or AKS ingress failure.

**Phase 5:** Restore the client service without redeploying the app.

```powershell
./scripts/scenarios/ClientService.ps1 -Action Reset
./scripts/scenarios/ClientService.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm all customer paths and complete shared recovery.

## 06. BadConfig: Invalid Backend Release Setting

**Phase 1:** Complete the shared baseline and note the backend's healthy configuration checks.

**Phase 2:** Replace the backend release setting with the scenario's invalid value.

```powershell
./scripts/scenarios/BadConfig.ps1 -Action Inject
./scripts/scenarios/BadConfig.ps1 -Action Verify
./scripts/scenarios/BadConfig.ps1 -Action Status
```

**Phase 3:** Backend shop requests should reject the invalid configuration; catalog and order operations fail. The image path remains independent. A running process is not sufficient evidence of application health.

**Phase 4:** Expect Dependency. SRE prompt:

> The backend is present but rejects catalog and order operations. Compare configuration validation, process health, and recent changes before assuming a network failure. Identify the invalid setting from available evidence and propose a scoped configuration rollback.

**Phase 5:** Restore the captured setting.

```powershell
./scripts/scenarios/BadConfig.ps1 -Action Reset
./scripts/scenarios/BadConfig.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Verify configuration acceptance and complete shared recovery.

## 07. DnsRecordMissing: Backend Name Missing

**Phase 1:** Complete the shared baseline and inspect the backend A record in `srelab.internal`.

**Phase 2:** Remove the captured backend record.

```powershell
./scripts/scenarios/DnsRecordMissing.ps1 -Action Inject
./scripts/scenarios/DnsRecordMissing.ps1 -Action Verify
./scripts/scenarios/DnsRecordMissing.ps1 -Action Status
```

**Phase 3:** After DNS cache and connection effects expire, catalog and order requests should fail because the client cannot resolve the backend. Check media independently. Record actual resolution evidence rather than assuming immediate failure.

**Phase 4:** Expect Dependency once failing health requests are logged. SRE prompt:

> Backend-dependent shop operations fail. Check name resolution from the relevant workload networks, distinguish a missing record from an unreachable resolved address, and correlate private-zone changes with the first failed request.

**Phase 5:** Restore the saved record and allow cache recovery.

```powershell
./scripts/scenarios/DnsRecordMissing.ps1 -Action Reset
./scripts/scenarios/DnsRecordMissing.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm resolution and requests, then complete shared recovery.

## 08. DnsRecordWrong: Backend Resolves To The Wrong Address

**Phase 1:** Complete the shared baseline. The intended backend private IP is `10.70.2.4`.

**Phase 2:** Point the backend record at unused `10.70.2.250`.

```powershell
./scripts/scenarios/DnsRecordWrong.ps1 -Action Inject
./scripts/scenarios/DnsRecordWrong.ps1 -Action Verify
./scripts/scenarios/DnsRecordWrong.ps1 -Action Status
```

**Phase 3:** Fresh backend-dependent requests should time out or fail after caches refresh. DNS may return an answer successfully while returning the wrong destination.

**Phase 4:** Expect Dependency. SRE prompt:

> Backend requests fail even though DNS returns an address. Compare the returned address with the actual backend NIC and service endpoint. Explain how a successful DNS query can still produce an availability incident, and separate this from routing or NSG failure.

**Phase 5:** Restore the captured A record.

```powershell
./scripts/scenarios/DnsRecordWrong.ps1 -Action Reset
./scripts/scenarios/DnsRecordWrong.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm the correct destination and complete shared recovery.

## 09. DnsLinkMissing: Application DNS Unavailable To Services VNet

**Phase 1:** Complete the shared baseline and compare application-zone VNet links.

**Phase 2:** Remove only the services VNet link from `srelab.internal`.

```powershell
./scripts/scenarios/DnsLinkMissing.ps1 -Action Inject
./scripts/scenarios/DnsLinkMissing.ps1 -Action Verify
./scripts/scenarios/DnsLinkMissing.ps1 -Action Status
```

**Phase 3:** Client-to-backend catalog and order operations should fail after cache effects. AKS may still resolve and reach the backend through its own zone link; that does not prove the client VM's path works.

**Phase 4:** Expect Dependency. SRE prompt:

> Backend access differs between the client VM and AKS. Compare private DNS visibility from each network, including zone links, before diagnosing the backend itself. Identify which caller loses resolution and which customer operations use that caller.

**Phase 5:** Recreate the captured services link.

```powershell
./scripts/scenarios/DnsLinkMissing.ps1 -Action Reset
./scripts/scenarios/DnsLinkMissing.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Validate both caller paths and complete shared recovery.

## 10. RouteBlackhole: Client Traffic Discarded

**Phase 1:** Complete the shared baseline; inspect the client subnet route table before mutation.

**Phase 2:** Add the reserved backend `/32` route with next hop None.

```powershell
./scripts/scenarios/RouteBlackhole.ps1 -Action Inject
./scripts/scenarios/RouteBlackhole.ps1 -Action Verify
./scripts/scenarios/RouteBlackhole.ps1 -Action Status
```

**Phase 3:** Client-to-backend catalog and order calls should fail while direct AKS-to-backend requests can remain healthy. Images have a separate destination and may still load.

**Phase 4:** Expect Dependency from client health. SRE prompt:

> The client cannot reach the backend, but another network path can. DNS resolves correctly. Compare subnet associations and effective route selection for the exact backend address; distinguish a discarded route from an NSG deny or stopped service.

**Phase 5:** Remove the scenario-owned route.

```powershell
./scripts/scenarios/RouteBlackhole.ps1 -Action Reset
./scripts/scenarios/RouteBlackhole.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Validate client reachability and complete shared recovery.

## 11. RouteWrongHop: Client Traffic Sent To An Unused Appliance

**Phase 1:** Complete the shared baseline and confirm the reserved incident route is absent.

**Phase 2:** Route backend `/32` traffic through unused appliance address `10.70.1.250`.

```powershell
./scripts/scenarios/RouteWrongHop.ps1 -Action Inject
./scripts/scenarios/RouteWrongHop.ps1 -Action Verify
./scripts/scenarios/RouteWrongHop.ps1 -Action Status
```

**Phase 3:** Backend-dependent shop requests should fail despite correct DNS and a running backend. Compare the unaffected direct path where available.

**Phase 4:** Expect Dependency. SRE prompt:

> Client-to-backend calls fail while the destination service appears healthy. Inspect the selected next hop and whether it is a real forwarding appliance. Distinguish misrouting from an explicit discard route and identify the smallest reversible correction.

**Phase 5:** Remove only the captured scenario-created route.

```powershell
./scripts/scenarios/RouteWrongHop.ps1 -Action Reset
./scripts/scenarios/RouteWrongHop.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Complete shared recovery before changing network controls again.

## 12. NsgBackend: Backend Port Blocked

**Phase 1:** Complete the shared baseline and record the workload NSG rule and priority.

**Phase 2:** Temporarily replace the captured application allow rule with a backend-port deny.

```powershell
./scripts/scenarios/NsgBackend.ps1 -Action Inject
./scripts/scenarios/NsgBackend.ps1 -Action Verify
./scripts/scenarios/NsgBackend.ps1 -Action Status
```

**Phase 3:** Fresh backend HTTP requests on port 8081 should fail, affecting catalog and orders. Existing connections may delay the symptom. Verify actual new requests rather than just the ARM rule state.

**Phase 4:** Expect Dependency. SRE prompt:

> Backend HTTP connections fail even though the VM and application may be running. Compare effective network-security rules, priorities, source scope and destination port against the intended flow. Separate packet filtering from DNS and route failures; do not recommend a broad Internet allow rule.

**Phase 5:** Restore the exact captured NSG rule.

```powershell
./scripts/scenarios/NsgBackend.ps1 -Action Reset
./scripts/scenarios/NsgBackend.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Verify the private path and complete shared recovery.

## 13. StorageRbac: Image Authorization Denied

**Phase 1:** Complete the shared baseline. Identify the shared VM workload identity, not the operator or SRE identity.

**Phase 2:** Remove only its captured Blob reader assignment.

```powershell
./scripts/scenarios/StorageRbac.ps1 -Action Inject
./scripts/scenarios/StorageRbac.ps1 -Action Verify
./scripts/scenarios/StorageRbac.ps1 -Action Status
```

**Phase 3:** After authorization propagation, fresh media retrieval should fail while catalog and checkout can work. The shop may surface a generic upstream error; inspect dependency evidence to establish authorization denial. Cached tokens or other inherited grants can mask the removal. Do not remove unrelated roles to force a failure.

**Phase 4:** Expect Dependency only after storage requests actually fail. SRE prompt:

> Images fail while the shop's other operations remain available. Determine whether the image caller reaches Blob Storage but lacks data-plane authorization. Identify the caller and effective role scope, compare recent role changes, and distinguish permission denial from private-network failure.

**Phase 5:** Restore the captured assignment and allow authorization propagation.

```powershell
./scripts/scenarios/StorageRbac.ps1 -Action Reset
./scripts/scenarios/StorageRbac.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Show fresh images and complete shared recovery; record an inconclusive injection honestly if access never failed.

## 14. VaultRbac: Checkout Secret Authorization Denied

**Phase 1:** Complete the shared baseline and save an existing order reference.

**Phase 2:** Remove only the workload identity's captured Key Vault Secrets User assignment.

```powershell
./scripts/scenarios/VaultRbac.ps1 -Action Inject
./scripts/scenarios/VaultRbac.ps1 -Action Verify
./scripts/scenarios/VaultRbac.ps1 -Action Status
```

**Phase 3:** After propagation, new checkout should fail while images, catalog and saved-order lookup work. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout` for a fresh attempt. A completed-order retry is not a secret-access test. If another grant preserves access, report that instead of expanding the fault.

**Phase 4:** Expect Dependency when vault probes fail. SRE prompt:

> New checkout fails but browsing and old orders work. Compare the checkout identity's Key Vault data-plane authorization with endpoint and DNS health. Explain how the evidence differs from a private-endpoint outage. Identify the minimum missing permission without exposing secrets.

**Phase 5:** Restore the exact captured assignment.

```powershell
./scripts/scenarios/VaultRbac.ps1 -Action Reset
./scripts/scenarios/VaultRbac.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm fresh checkout and complete shared recovery.

## 15. BlobDns: Blob Private DNS Link Missing

**Phase 1:** Complete the shared baseline and capture Blob name resolution from the services VNet. **Known limitation:** an earlier rehearsal did not produce the expected failure; this test is exploratory, not a guaranteed outage demo.

**Phase 2:** Remove the Blob private-zone services VNet link.

```powershell
./scripts/scenarios/BlobDns.ps1 -Action Inject
./scripts/scenarios/BlobDns.ps1 -Action Verify
./scripts/scenarios/BlobDns.ps1 -Action Status
```

**Phase 3:** Expect image failure only if the client loses working private resolution/connectivity. Observe fresh media requests after caching effects. If they still succeed, record actual resolution and the failed hypothesis; do not change additional DNS or networking to manufacture the result.

**Phase 4:** Dependency fires only if failed storage probes reach Log Analytics. SRE prompt:

> Assess Blob name resolution from the image-fetching client and compare it with the effective private endpoint path. Images are [observed result]. Explain whether DNS caching, alternate resolution, or remaining connectivity accounts for the result, and state whether a customer outage is actually demonstrated.

**Phase 5:** Restore the removed link even if the intended symptom never appeared.

```powershell
./scripts/scenarios/BlobDns.ps1 -Action Reset
./scripts/scenarios/BlobDns.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Complete shared recovery. A recovered-only result is not a successful injection result.

## 16. VaultDns: Vault Private DNS Link Missing

**Phase 1:** Complete the shared baseline and note vault resolution from the services network.

**Phase 2:** Remove the Vault private-zone services VNet link.

```powershell
./scripts/scenarios/VaultDns.ps1 -Action Inject
./scripts/scenarios/VaultDns.ps1 -Action Verify
./scripts/scenarios/VaultDns.ps1 -Action Status
```

**Phase 3:** New checkout should fail if the backend loses its working private vault path. Catalog, images and existing-order lookup should remain independent. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout` after cache effects; record actual behavior rather than assuming link deletion alone proves an outage.

**Phase 4:** Expect Dependency if vault probes fail. SRE prompt:

> Checkout secret access fails while unrelated shop operations work. Compare the vault hostname's resolution from the workload network, private-zone links, and endpoint state. Distinguish a resolution-path failure from missing permissions or a deleted private endpoint.

**Phase 5:** Restore the captured DNS link.

```powershell
./scripts/scenarios/VaultDns.ps1 -Action Reset
./scripts/scenarios/VaultDns.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Prove fresh checkout and complete shared recovery.

## 17. BackendVm: Backend Compute Unavailable

**Phase 1:** Complete the shared baseline; note backend power state and latest heartbeat.

**Phase 2:** Deallocate the backend VM.

```powershell
./scripts/scenarios/BackendVm.ps1 -Action Inject
./scripts/scenarios/BackendVm.ps1 -Action Verify
./scripts/scenarios/BackendVm.ps1 -Action Status
```

**Phase 3:** Catalog, checkout and lookup should fail. The client Blob path can remain available. Observe VM power independently of application reachability; backend heartbeats will become stale.

**Phase 4:** Expect Dependency from the still-running client. The Telemetry rule is not reliable proof of the VM outage. SRE prompt:

> Backend-dependent requests fail and backend telemetry becomes stale. Correlate compute power state and resource activity with the last successful requests. Distinguish VM deallocation from an application-service failure and explain which diagnostics are unavailable while the VM is stopped.

**Phase 5:** Start the same VM through the captured-state reset; guest commands are not required to power it on.

```powershell
./scripts/scenarios/BackendVm.ps1 -Action Reset
./scripts/scenarios/BackendVm.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Check the baseline order survives, wait for fresh heartbeat, and complete shared recovery.

## 18. ClientVm: Customer API Path And Probe Both Lost

**Phase 1:** Complete the shared baseline; note client power, heartbeat and probe freshness.

**Phase 2:** Deallocate the client VM.

```powershell
./scripts/scenarios/ClientVm.ps1 -Action Inject
./scripts/scenarios/ClientVm.ps1 -Action Verify
./scripts/scenarios/ClientVm.ps1 -Action Status
```

**Phase 3:** All shop API requests should fail; the AKS-served or cached page shell may remain visible. The backend can still be healthy. The client probe also stops, so there may be no new dependency-failure rows.

**Phase 4:** No reliable new alert is guaranteed. The missing-telemetry query has the limitations described above. Use a manual investigation if no incident arrives. SRE prompt:

> Customer APIs fail together and client probe logs stop arriving. Determine whether the client compute is unavailable or telemetry alone is broken. Explain why absence of failing probe rows cannot establish health, and identify the alerting blind spot without modifying monitoring.

**Phase 5:** Restore client compute and wait for both requests and probe emission.

```powershell
./scripts/scenarios/ClientVm.ps1 -Action Reset
./scripts/scenarios/ClientVm.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Require a fresh client heartbeat in shared recovery; record detection separately from customer impact.

## 19. AksBadImage: Web Image Pull Failure

**Phase 1:** Complete the shared baseline; note web image and available replicas. AKS scenarios temporarily use Recreate so an old healthy pod cannot mask the replacement failure.

**Phase 2:** Replace the web image with a nonexistent tag.

```powershell
./scripts/scenarios/AksBadImage.ps1 -Action Inject
./scripts/scenarios/AksBadImage.ps1 -Action Verify
./scripts/scenarios/AksBadImage.ps1 -Action Status
```

**Phase 3:** Fresh public shop requests should fail through the gateway, commonly as upstream errors. Cached HTML is not proof of availability. Inspect ErrImagePull/ImagePullBackOff and zero available web replicas.

**Phase 4:** Expect Pod if Container Insights ingests the failure. VM dependency probes may stay healthy. SRE prompt:

> The public shop is unavailable while VM dependencies appear healthy. Inspect the web rollout, image reference, pull events and available replicas. Distinguish a nonexistent image from registry authorization or connectivity failure and propose a rollback to the last known working specification.

**Phase 5:** Restore the full captured deployment spec, including rollout strategy.

```powershell
./scripts/scenarios/AksBadImage.ps1 -Action Reset
./scripts/scenarios/AksBadImage.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm Ready/available web replicas and complete shared recovery; historical pod rows can delay alert resolution.

## 20. AksCrashLoop: Web Process Exits Repeatedly

**Phase 1:** Complete the shared baseline and record web restart counts.

**Phase 2:** Replace the web command with a process that exits with code 42.

```powershell
./scripts/scenarios/AksCrashLoop.ps1 -Action Inject
./scripts/scenarios/AksCrashLoop.ps1 -Action Verify
./scripts/scenarios/AksCrashLoop.ps1 -Action Status
```

**Phase 3:** Public requests should fail; observe restarts, last termination and eventual backoff. Distinguish a pulled/running-then-exiting image from an image that never starts.

**Phase 4:** Expect Pod after failure evidence is ingested. SRE prompt:

> The web workload repeatedly restarts and cannot serve the shop. Correlate the current command, termination exit code, restart count and available logs with the recent rollout. Explain why this is a process-exit failure rather than an image-pull or readiness-only problem.

**Phase 5:** Restore the original web specification.

```powershell
./scripts/scenarios/AksCrashLoop.ps1 -Action Reset
./scripts/scenarios/AksCrashLoop.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Check stable readiness and complete shared recovery.

## 21. AksReadiness: Running Pod Removed From Service

**Phase 1:** Complete the shared baseline; record the working readiness path and service endpoints.

**Phase 2:** Point the readiness probe to a nonexistent path.

```powershell
./scripts/scenarios/AksReadiness.ps1 -Action Inject
./scripts/scenarios/AksReadiness.ps1 -Action Verify
./scripts/scenarios/AksReadiness.ps1 -Action Status
```

**Phase 3:** The pod may be Running while not Ready, leaving the web Service without ready backends. Fresh public requests should fail. Show readiness and service endpoint evidence, not only pod phase.

**Phase 4:** The Pod rule does not explicitly check readiness; a new alert is not guaranteed. Use a manual investigation when needed. SRE prompt:

> The web pod is Running, yet customers cannot reach the application. Compare readiness results, probe configuration, deployment availability and service endpoints. Explain the difference between Running and Ready, and assess whether the current alert query detects this state.

**Phase 5:** Restore the original probe through the captured deployment spec.

```powershell
./scripts/scenarios/AksReadiness.ps1 -Action Reset
./scripts/scenarios/AksReadiness.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm ready endpoints and complete shared recovery.

## 22. AksScheduling: No Eligible Node

**Phase 1:** Complete the shared baseline; note the web node selector and available node labels.

**Phase 2:** Apply an unsatisfiable selector to the web pod template.

```powershell
./scripts/scenarios/AksScheduling.ps1 -Action Inject
./scripts/scenarios/AksScheduling.ps1 -Action Verify
./scripts/scenarios/AksScheduling.ps1 -Action Status
```

**Phase 3:** The replacement pod should remain Pending with FailedScheduling evidence; fresh shop requests fail. No application logs may exist because the container never started.

**Phase 4:** Expect Pod from Pending inventory when collected. SRE prompt:

> The replacement web pod remains Pending and the shop is unavailable. Inspect scheduler events, node labels, selector constraints and resource requests. Distinguish a placement constraint from insufficient capacity before recommending additional nodes.

**Phase 5:** Restore the original placement configuration.

```powershell
./scripts/scenarios/AksScheduling.ps1 -Action Reset
./scripts/scenarios/AksScheduling.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm scheduling and readiness, then complete shared recovery.

## 23. AksOom: Container Memory Limit Exceeded

**Phase 1:** Complete the shared baseline and note the web container's memory limit. This is a container-limit test, not host-memory stress.

**Phase 2:** Run the bounded scenario allocation beyond the existing container limit.

```powershell
./scripts/scenarios/AksOom.ps1 -Action Inject
./scripts/scenarios/AksOom.ps1 -Action Verify
./scripts/scenarios/AksOom.ps1 -Action Status
```

**Phase 3:** The shop should become unavailable. Verify termination evidence actually says OOMKilled; exit code alone is insufficient. Capture limits, restart history and available memory observations.

**Phase 4:** Expect Pod if OOM or related failure state is captured in inventory. SRE prompt:

> The web container terminates under memory allocation and the shop becomes unavailable. Inspect the termination reason, container limit, restart history and node state. Distinguish a container cgroup limit breach from node-wide memory exhaustion; justify recovery without automatically increasing limits.

**Phase 5:** Restore the original process and deployment spec.

```powershell
./scripts/scenarios/AksOom.ps1 -Action Reset
./scripts/scenarios/AksOom.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm stable service and complete shared recovery.

## 24. Web Scale-To-Zero: No Serving Replicas

**Phase 1:** Complete the shared baseline. Confirm web is serving and neither catalog-scenario nor web-outage recovery state is active.

**Phase 2:** This legacy script has Inject, Status and Reset only; do not pass Verify or Expected.

```powershell
./scripts/Set-WebOutage.ps1 -Action Inject
./scripts/Set-WebOutage.ps1 -Action Status
```

**Phase 3:** Show desired replicas zero and no serving web pods. Fresh public shop requests should fail through Caddy; a previously loaded page can remain visible. Run the public-shop test to observe failure, but do not interpret its first error as proof about every dependency.

**Phase 4:** No dedicated zero-replica/public-availability alert exists. Pod inventory may show transient records but does not reliably detect deliberate absence. VM dependency checks can stay healthy. SRE prompt:

> The public shop is unavailable, but dependency services remain healthy and no crashing pod is visible. Compare desired and available replicas, ready endpoints and recent scale changes. Explain why a pod-failure query can miss a deployment with zero pods.

**Phase 5:** Restore the captured replica count. Reset checks rollout and internal reachability; validate the public path separately.

```powershell
./scripts/Set-WebOutage.ps1 -Action Reset
./scripts/Set-WebOutage.ps1 -Action Status
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm the saved web recovery record is cleared and complete shared recovery.

## 25. ArmRbac: Management Access Fails, Shopping Survives

**Phase 1:** Complete the shared baseline, including the separate ARM dependency check. The public shop does not expose `/health` or `/api/status`.

**Phase 2:** Remove only the VM identity's captured resource-group Reader assignment.

```powershell
./scripts/scenarios/ArmRbac.ps1 -Action Inject
./scripts/scenarios/ArmRbac.ps1 -Action Verify
./scripts/scenarios/ArmRbac.ps1 -Action Status
```

**Phase 3:** After propagation, the private ARM dependency check should fail while browsing, images and checkout can remain healthy. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout` to demonstrate independence. The ten-check operations badge does not include this ARM check; use scenario/private application evidence.

**Phase 4:** Expect Dependency from failed `arm` probes. SRE prompt:

> A management-plane dependency check fails while customer shopping still works. Identify the identity making that request and distinguish resource-group Reader from Blob and Vault data-plane permissions. Explain why this alert does not by itself prove a customer outage.

**Phase 5:** Restore the captured Reader grant; account for propagation or inherited access.

```powershell
./scripts/scenarios/ArmRbac.ps1 -Action Reset
./scripts/scenarios/ArmRbac.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm the ARM check itself recovers and complete shared recovery.

## 26. KubeRbac: Operator Access Denied

**Phase 1:** Complete the shared baseline and observe the private operator authorization check. Distinguish the namespace operator identity from the privileged Run Command observer.

**Phase 2:** Empty the captured operator RoleBinding subjects while preserving object identity.

```powershell
./scripts/scenarios/KubeRbac.ps1 -Action Inject
./scripts/scenarios/KubeRbac.ps1 -Action Verify
./scripts/scenarios/KubeRbac.ps1 -Action Status
```

**Phase 3:** Operator access should be denied while the shop can remain fully usable. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout`; use the private operations evidence for denial. Successful privileged observation does not prove the operator still has permission.

**Phase 4:** No dedicated operator-RBAC alert exists. SRE prompt:

> The application works, but the intended Kubernetes operator cannot perform its normal pod-access operation. Compare the operator's identity and RoleBinding subjects with the observer's privileges. Identify the precise missing binding and propose restoration without granting cluster-admin.

**Phase 5:** Restore captured binding subjects; restoration checks the original UID.

```powershell
./scripts/scenarios/KubeRbac.ps1 -Action Reset
./scripts/scenarios/KubeRbac.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Prove operator authorization recovers and complete shared recovery.

## 27. CpuPressure: Bounded Backend CPU Stress

**Phase 1:** Complete the shared baseline and record backend CPU plus customer response observations before stress.

**Phase 2:** Start one bounded CPU worker with a 90% quota.

```powershell
./scripts/scenarios/CpuPressure.ps1 -Action Inject
./scripts/scenarios/CpuPressure.ps1 -Action Verify
./scripts/scenarios/CpuPressure.ps1 -Action Status
```

**Phase 3:** The operations CPU check turns unhealthy at measured busy CPU >=75%. Shopping may slow down or remain normal; do not claim an outage without failed requests. Run `./scripts/Test-PublicShop.ps1 -IncludeCheckout` and compare observed behavior with baseline. If the measured threshold is not crossed, report the verification result rather than increasing stress.

**Phase 4:** No dedicated CPU alert exists. Dependency can fire only if requests actually fail. SRE prompt:

> Backend CPU is elevated during this interval. Correlate measured resource use and the active process with request success and latency. Separate resource pressure from proven customer impact, identify the source, and propose bounded recovery without changing VM size by default.

**Phase 5:** Stop the owned stress unit and clear recovery state even if its ten-minute bound already expired.

```powershell
./scripts/scenarios/CpuPressure.ps1 -Action Reset
./scripts/scenarios/CpuPressure.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Confirm measured CPU recovery and complete shared recovery.

## 28. MemoryPressure: Bounded Working-Set Growth

**Phase 1:** Complete the shared baseline and record backend memory. Unlike AksOom, this test is designed not to exhaust host memory.

**Phase 2:** Start the bounded 256 MiB allocation, constrained by the stress service's memory limit.

```powershell
./scripts/scenarios/MemoryPressure.ps1 -Action Inject
./scripts/scenarios/MemoryPressure.ps1 -Action Verify
./scripts/scenarios/MemoryPressure.ps1 -Action Status
```

**Phase 3:** The memory check fails at >=85% host use or >=128 MiB measured stress working set. That test-specific threshold is not proof of host exhaustion. Shopping may remain healthy; run `./scripts/Test-PublicShop.ps1 -IncludeCheckout` and record actual impact.

**Phase 4:** No dedicated memory-pressure alert exists. SRE prompt:

> The backend memory operations check is unhealthy. Compare host utilization with the bounded stress process working set and its limit. Determine whether the result indicates controlled consumption, host pressure, or an actual OOM. Explain any customer impact separately from the test threshold.

**Phase 5:** Stop the owned worker and clear recovery state even after its automatic timeout.

```powershell
./scripts/scenarios/MemoryPressure.ps1 -Action Reset
./scripts/scenarios/MemoryPressure.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Verify the stress allocation is gone and complete shared recovery.

## 29. TelemetryGap: Monitoring Stops, Application Survives

**Phase 1:** Complete the shared baseline with fresh client and backend heartbeats. Note the backend AMA service state and last ingested telemetry time.

**Phase 2:** Apply the temporary startup-condition override and stop backend Azure Monitor Agent.

```powershell
./scripts/scenarios/TelemetryGap.ps1 -Action Inject
./scripts/scenarios/TelemetryGap.ps1 -Action Verify
./scripts/scenarios/TelemetryGap.ps1 -Action Status
```

**Phase 3:** AMA service evidence should fail promptly; the separate heartbeat operations check becomes unhealthy after ten minutes without a heartbeat. Scenario Verify targets AMA, so its success does not prove that the heartbeat threshold has elapsed. The shop should remain usable; run `./scripts/Test-PublicShop.ps1 -IncludeCheckout`.

**Phase 4:** The current Telemetry rule can briefly match stale rows but can miss or resolve the sustained gap after the host disappears from its window. Do not wait indefinitely for an automatic incident. SRE prompt:

> Customer requests still succeed, but backend telemetry stops advancing. Compare application reachability, VM power, monitoring-service state and last ingestion time. Explain whether missing data indicates an application outage or collection failure, and assess how the current heartbeat alert treats a completely absent host.

**Phase 5:** Remove the owned override and restore the originally active monitoring service.

```powershell
./scripts/scenarios/TelemetryGap.ps1 -Action Reset
./scripts/scenarios/TelemetryGap.ps1 -Action Verify -Expected Recovered
./scripts/Test-PublicShop.ps1 -IncludeCheckout
```

Wait for a newly ingested backend heartbeat and run the shared telemetry baseline. Service Running alone is not proof that collection resumed.

## Evidence Checklist And Exit Gate

Copy this checklist into your session notes for each test. Keep raw state, identifiers and logs in approved private storage; do not commit `.state`.

| Evidence | Record |
|---|---|
| Test and operator | Test number, scenario, operator |
| Baseline | UTC time, six healthy checks, public check result, baseline order ID |
| Injection | UTC time, intended mutation, Inject result |
| Failure verification | Verify result, Status evidence, observation timestamp |
| Customer impact | Fresh operation, HTTP/result, screenshot or request evidence |
| Unaffected path | Successful independent operation, where applicable |
| Alert detection | Rule, instance ID, Fired time; or expected gap/inconclusive result |
| SRE reception | Incident linkage, thread, response plan, automatic vs manual |
| Diagnosis | Evidence-supported cause, alternatives, missing access or telemetry |
| Recovery | Reset result, recovered Verify result, public order and lookup |
| Monitoring recovery | Fresh telemetry, monitor condition Resolved, SRE status |
| Outcome | Passed, failed, or inconclusive for each layer; follow-up needed |

For catalog scenarios, failure/recovery observations are stored under `.state/verification/<Scenario>-Injected.json` and `<Scenario>-Recovered.json`; completed captured state is archived under `.state/history`. These files are local evidence, not a substitute for fresh customer tests. The web scale-to-zero script has a separate `.state/web-outage.json` recovery record and does not produce the same scenario Verify files.

**Proceed only after the previous resource state is restored and the healthy checks pass.** If automatic detection is a goal, also wait for the relevant rule to resolve. An app failure/recovery pass does not imply an alerting or SRE automation pass.

## Final Session Checks

After the last reset, confirm no active incident or web-outage state remains, then run:

```powershell
./scripts/Test-Lab.ps1 -IncludeTelemetry
./scripts/Test-PublicShop.ps1 -IncludeCheckout
./scripts/Set-WebOutage.ps1 -Action Status
```

Do not stop at a visible storefront: require images, a fresh checkout, persisted lookup and fresh telemetry. Confirm resolved alerts separately. This runbook does not shut down resources; the deployed lab continues to incur charges.

## SRE Integration References

- [Azure Monitor alerts in Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/azure-monitor-alerts)
- [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans)
- [SRE Agent API reference](https://learn.microsoft.com/en-us/azure/sre-agent/api-reference)