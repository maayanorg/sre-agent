# Customer Demo: Healthy, Unavailable, Recovered

**Shop deployed:** Use [SHOP.md](SHOP.md) for the Azure-hosted Fieldnote storefront and verified customer-impact scenarios. This guide describes the Azure health dashboard, now at `/health`.

For a folder-by-folder file list and the first-time/daily execution order, start with [the simple script guide](README.md).

The frontend is deployed in `aks-srelab-swc-001`, namespace `srelab`, as `deployment/web`. The shop is public at https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com/ without a localhost process. This runbook's operator dashboard remains private and displays real HTTP checks for AKS Web, Backend API, Client API, Blob Storage, Key Vault and Azure Resource Manager. There is no simulated success data or browser-accessible fault control. See [SHOP.md](SHOP.md) for public shop demonstrations.

## Start The Viewer

Use PowerShell 7, Node.js and an authenticated Azure CLI session authorized for this lab and AKS Run Command. From the workspace root, while web is healthy:

```powershell
./scripts/Start-DemoViewer.ps1 -Port 8090
```

For the private operator dashboard, open **http://127.0.0.1:8090/health** and keep this terminal running. Use another free port if 8090 is occupied. This optional viewer binds only to loopback. Customers can open the public shop URL directly on their own devices.

Wait for **Applications healthy**, **6 / 6**, and **Operations healthy**. The page includes request latency, observation age, recent history and session status changes. Pause/resume controls observation display, not workloads.

## Operational Failures Without Application Outages

The top summary and Operations & observability section show failures independently of application availability. For example:

```powershell
./scripts/scenarios/KubeRbac.ps1 -Action Inject
./scripts/scenarios/KubeRbac.ps1 -Action Verify
./scripts/scenarios/KubeRbac.ps1 -Action Status
./scripts/scenarios/KubeRbac.ps1 -Action Reset
```

The customer sees **6 / 6** application checks alongside **1 operational failure** and denied operator access. The permission probe uses an isolated kubeconfig so the observer's privileged credentials cannot hide the denial.

`TelemetryGap` similarly stops monitoring without stopping the app. Its runtime-only service override prevents automatic restarts; reset removes the dedicated override. AMA becomes failed first, while heartbeat evidence independently ages past its ten-minute limit. Resource pressure and VM power have their own measured checks. All 28 scripts and expected effects are in [SCENARIOS.md](SCENARIOS.md).

Operations are collected independently through the local Azure relay, with individual timestamps. A stale or unavailable observation becomes **Unknown**, not healthy or a claimed application outage. Direct AKS access without the local relay has no operations API.

## Demonstrate Failure And Recovery

In another PowerShell terminal at the workspace root:

```powershell
./scripts/Set-WebOutage.ps1 -Action Status
./scripts/Set-WebOutage.ps1 -Action Inject
```

Injection saves the Deployment UID and original replica count under ignored `.state/web-outage.json`, scales only `deployment/web` to zero and waits for its pods to terminate. The probe remains running. The browser changes to **Web application unavailable**; dependency rows become **Unknown**, since web cannot report current dependency observations. This is a deliberate service stop, not a crash or an OOM demonstration.

Restore using the same workspace, preserving the recovery file:

```powershell
./scripts/Set-WebOutage.ps1 -Action Reset
```

Reset validates the Deployment UID, restores the saved replica count, waits for rollout and verifies `/healthz`. Recovery state is removed only after success. The browser returns to **Applications healthy** after the next successful collection and relay refresh. Both actions support `-WhatIf`; repeated injection is refused until reset. Failed reset keeps recovery state so it can be retried.

For scripted demonstrations, always restore in `finally` after a successful injection. Do not delete the recovery file to bypass the guard or redeploy workloads during an active incident.

## What The Browser Proves

The HTML and status API run in AKS. Because the cluster is private and this laptop has no provisioned private connection, the viewer fetches the AKS page at startup and retains that page locally. It then uses AKS Run Command to execute HTTP checks from the independent probe. The retained page is why an outage can remain visible after the actual web pod stops; it does not mean AKS web is still serving.

Each relay refresh waits for Run Command to finish, then waits 15 seconds before starting another. Allow tens of seconds for state changes, potentially longer under Azure load. Observe the displayed timestamp. Browser polling does not accelerate the Azure relay. A relay/control-plane failure shows an unavailable observation, not proof of a web outage. Relay observations older than 120 seconds are not shown as current health; the AKS API also marks its own snapshots stale after 45 seconds.

The frontend checks backend directly and the client VM's four endpoints. The client uses its managed identity to access Storage, Key Vault and ARM. Only status fields are exposed; response bodies and identity tokens are not returned. Dependency failures leave `/healthz` healthy so the frontend can continue explaining the failure. The dashboard is synthetic request monitoring, not Log Analytics or distributed tracing.

An operator with existing private network connectivity and an authorized Kubernetes context can instead run `kubectl -n srelab port-forward service/web 8088:80` and browse `http://localhost:8088`. Direct access has less delay, but loses the page/API connection when web stops. Private laptop connectivity is not created by these scripts.

## Redeploy And Verify

```powershell
./scripts/Deploy-Frontend.ps1
./tests/Validate-Local.ps1
./scripts/Test-Lab.ps1 -IncludeTelemetry
```

Restart an optional viewer after frontend HTML changes so it loads the new AKS page. Initialization also uses the same frontend manifest. Content-hashed immutable ConfigMaps preserve prior source revisions for rollback; old revisions are not automatically pruned. The public gateway is managed separately with Set-PublicShop.ps1; see SHOP.md.

## Verified On 2026-09-15

- Five local frontend tests passed; all PowerShell scripts parsed and Node source syntax checks passed.
- Desktop (1440 x 1000) and mobile (390 x 844) browser checks passed without horizontal overflow. The history canvas rendered and pause/resume cleared/restored current health.
- Actual web scale-to-zero produced the unavailable browser state with one failed web check and zero current healthy rows.
- Reset restored a ready web pod and all six healthy checks. The browser recorded healthy, unavailable and recovered states.
- Full live baseline passed after recovery: VM services, disk, DNS, dependencies, frontend, Kubernetes RBAC, agent provisioning and fresh heartbeats. Evidence is in ignored `.state/baseline-verification.json`.

The additional scenario implementation now includes independent operations checks and all 28 entry scripts. Live verification snapshots and archived recovery records are under `.state/verification` and `.state/history`; see [SCENARIOS.md](SCENARIOS.md) for their interpretation. SRE Agent investigation remains a separate, unverified workflow; this demonstration does not claim automatic agent remediation. See [ARCHITECTURE.md](ARCHITECTURE.md) for the complete connections and limitations.