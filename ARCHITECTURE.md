# SRE Day Lab Architecture

**Migration note:** Fieldnote was deployed on 2026-09-22. This page describes the underlying lab and its health checks, now at `/health`. The storefront, real data dependencies and verified shop failures are documented in [SHOP.md](SHOP.md).

## What You Have Today

This is a deployed incident-response training environment, not yet a complete incident demonstration package. Infrastructure deployment, workload initialization and the healthy baseline check passed on 2026-09-15, including fresh heartbeats from both VMs. This document describes that verified baseline and the current source definitions; it is not a new live health check.

**There is a live shop and status frontend in AKS:** a Node.js web pod serves the shop and a private dashboard checking the backend VM, client VM, Blob Storage, Key Vault and ARM paths. A separate probe pod remains available when the frontend stops. The public shop uses an Azure Load Balancer and non-root Caddy HTTPS gateway, forwarding only the storefront and allowlisted shop APIs to the private web Service. The optional localhost viewer still retrieves private operations observations through Azure Run Command. See [SHOP.md](SHOP.md) for the public URL, request limits and costs.

**The web outage demonstration and 28 additional fault scripts are implemented.** The dashboard now separates application availability from operational health, including operator authorization, VM power, resource pressure and telemetry. See [the scenario guide](SCENARIOS.md) for individual scripts and live evidence records, and [the customer demo guide](DEMO.md) for presentation. SRE Agent investigation remains unverified.

See [the architecture diagrams and component inventory](.github/modernize/assessment/engines/facts/architecture-diagram.md).

## Deployment Boundary

| Item | Value |
|---|---|
| Subscription | `ME-MngEnvMCAP263992-mluxemburg-3` |
| Subscription ID | `15ba7e94-568d-4ba9-bb5d-29ed107ac109` |
| Region | Sweden Central |
| Main resource group | `rg-srelab-swedencentral-001` |
| AKS-managed resource group | `rg-srelab-aksnodes-swedencentral-001` |
| Identification | `Project=SRE-Day`, `Purpose=IncidentResponseLab`, `Environment=Demo`, `Owner=mluxemburg`, `Lifecycle=ReusableEvent`, `ManagedBy=Bicep` |

Directly managed infrastructure is in the main group. AKS creates its node infrastructure in the separate managed group. One node and single application replicas reduce cost, but do not provide production high availability.

## Applications And Dependencies

### AKS Workloads

Cluster: `aks-srelab-swc-001`. Namespace: `srelab`. One system node: `Standard_D2s_v4`.

| Component | Definition | Behavior |
|---|---|---|
| `deployment/web` | One replica, `node:22-alpine` | Serves dashboard and `/api/status` on TCP 8080; `/healthz` readiness and liveness probes |
| `service/web` | ClusterIP, port 80 -> pod port 8080 | Internal service discovery as `http://web` in the same namespace |
| `deployment/probe` | One replica, `curlimages/curl:8.12.1` | Every loop checks `http://web` and `http://backend.srelab.internal:8081/health`, then sleeps 15 seconds |
| `serviceaccount/operator` | `pod-reader` Role and `operator-reader` RoleBinding | Can get/list/watch pods and pod logs in `srelab`; used for Kubernetes RBAC scenarios |

The probe logs HTTP results but keeps running when a request fails. A `Running` probe pod does not mean its dependencies are healthy. Its loop reports status `000` for many connection/DNS failures; that is a curl result, not an HTTP response code.

The frontend calls backend `/health` directly through private DNS, and calls the client VM's four endpoints over VNet peering. The client VM performs the authenticated Storage, Key Vault and ARM requests using its managed identity; there is no AKS workload identity binding to these services. Checks run in parallel with a 12-second timeout, followed by a 10-second collection interval. HTTP result codes, latency and observation timestamps are exposed, not dependency response bodies or tokens.

The UI counts the responding web API plus five dependency checks. Dependency failures degrade the dashboard but do not fail `/healthz`: the page must remain available to display the failure. Missing/stale observations are shown as unknown, never as current healthy results. Source is mounted from a content-hashed immutable ConfigMap; the pod runs non-root with a read-only root filesystem and no mounted Kubernetes service-account token.

### VM Workloads

Both VMs are Ubuntu-based, private-only `Standard_B1ms` instances running a small Node.js service under systemd. They share the lab workload managed identity. Each has a 128 MiB loopback filesystem mounted at `/mnt/srelab-data`, providing an isolated application data target for the disk-full fault, not a separate Azure managed data disk.

| VM | Address | Application role |
|---|---|---|
| `vm-srelab-client-swc-001` | `10.70.1.4:8080` | Dependency-checking application; a timer checks its four endpoints approximately every minute |
| `vm-srelab-backend-swc-001` | `10.70.2.4:8081` | Backend service, reachable as `backend.srelab.internal` |

The Node.js application exposes these independent endpoints:

| Endpoint | What it checks | Failure result |
|---|---|---|
| `/health` | Valid `v1` configuration and a 4 KiB data-file write; the client additionally calls backend `/health` | HTTP 503 on caught configuration, disk or backend errors |
| `/storage` | Gets a managed-identity token and lists blobs in the private `lab` container | HTTP 503 on caught network/auth/service errors |
| `/vault` | Gets a managed-identity token and lists secret metadata | HTTP 503 on caught network/auth/service errors |
| `/arm` | Gets a managed-identity token and reads the lab resource group through Azure Resource Manager | HTTP 503 on caught permission/network/API errors |

Successful requests return HTTP 200 with `{"status":"healthy"}`. These checks do not require a populated blob container or an application secret value. The app is not a database-backed business application. `/health` does not aggregate `/storage`, `/vault` or `/arm`; a Storage failure alone does not make `/health` fail. A stopped service or unreachable VM cannot return an HTTP 503; callers instead see a connection error or timeout.

## Network Connections

| Network element | Address or configuration | Purpose |
|---|---|---|
| Services VNet | `vnet-srelab-services-swc-001`, `10.70.0.0/16` | Hosts the two VMs and private endpoints |
| Client subnet | `10.70.1.0/24` | Client VM, lab NSG, route table and NAT gateway |
| Backend subnet | `10.70.2.0/24` | Backend VM, same lab NSG and NAT gateway |
| Private endpoint subnet | `10.70.3.0/24` | Blob and Key Vault private endpoint NICs; endpoint network policies disabled |
| AKS VNet/subnet | `10.71.0.0/16`, subnet `10.71.0.0/22` | AKS nodes; bidirectional peering with the services VNet |
| AKS overlay pod range | `10.244.0.0/16` | Pod addresses; not directly routed from the services VNet |
| Kubernetes Service range | `10.72.0.0/16`, DNS `10.72.0.10` | Internal virtual service addresses |

Important paths:

1. **Browser -> localhost viewer -> AKS Run Command -> probe -> web:** the viewer obtains the page from AKS at startup and caches it locally. It retrieves real status snapshots and forwards allowlisted shop requests through the probe; Kubernetes DNS resolves `web` to its ClusterIP and forwards to the ready web pod on port 8080. This is a delayed relay, not a network tunnel. Shop checkout writes orders on the Azure backend VM. A stopped web workload leaves the cached UI visible so it can report the outage.
2. **Probe -> backend:** `backend.srelab.internal` resolves to `10.70.2.4`; overlay traffic leaving AKS is translated to a node IP, crosses VNet peering and reaches the backend on port 8081.
3. **Client -> backend:** the same DNS name resolves to `10.70.2.4`; the client subnet route table and VM subnet NSG can affect this path. A route fault scoped to the client subnet does not automatically affect the AKS probe path.
4. **VM -> Blob/Key Vault:** normal service hostnames resolve through private DNS to endpoint NICs in `10.70.3.0/24`; HTTPS crosses those private endpoints to the managed services. Public network access is disabled on both services.
5. **VM -> ARM and package repositories:** explicit outbound access uses the services NAT gateway and its public IP. This is egress, not a public application entrance. AKS has its own Standard Load Balancer outbound path.
6. **Frontend -> client/backend:** the web pod checks backend port 8081 directly and client port 8080 across peering. The client checks backend, Blob, Key Vault and ARM. A client-only route failure can therefore degrade client-dependent dashboard rows while the direct backend row remains healthy.

The three lab private DNS zones are linked to both VNets: `srelab.internal`, `privatelink.blob.core.windows.net`, and `privatelink.vaultcore.azure.net`. VNet peering alone does not replace these DNS links. The backend A record has a 30-second TTL. Kubernetes service DNS is separate from the Azure private DNS zones.

The shared NSG explicitly allows internal TCP 8080/8081 and retains Azure's default NSG rules. It is not a strict deny-all microsegmentation policy. The client route table is initially empty. No baseline Kubernetes NetworkPolicy is installed by the workload script, although AKS is configured with Calico support.

The Kubernetes API and web Service are private. A separate `public-shop` LoadBalancer exposes only HTTP/HTTPS through Caddy, with ACME certificates on a persistent managed disk. The additional subnet NSG permits only the shop public IP on ports 80/443. Scripts use Azure VM Run Command and AKS Run Command for operations without public VM management ports or a public Kubernetes API. The public gateway blocks dashboard/operations routes and cannot inject faults.

## Identities And SRE Agent

| Identity or actor | Configured access |
|---|---|
| `id-srelab-workload-swc-001` | Shared by both VMs; Reader on the main RG, Storage Blob Data Reader on the storage account, Key Vault Secrets User on the vault |
| `id-srelab-aks-swc-001` | AKS cluster identity; Network Contributor on the AKS VNet |
| `id-srelab-agent-swc-001` | Reader, Monitoring Reader and Log Analytics Reader on the main RG |
| Deploying user | Azure Kubernetes Service RBAC Cluster Admin on the cluster; SRE Agent Administrator on the agent |
| Kubernetes `operator` | Namespace-local pod/log read permissions; separate from the Azure user and managed identities |

`sre-srelab-swc-001` is provisioned in **Review** mode with the main resource group as its managed-resource scope. It has an Application Insights resource for agent logging. It is an investigation component, not in the application request path.

Provisioning is verified; a successful agent investigation is not yet verified. Review mode does not grant repair permissions. The configured reader roles do not authorize VM/AKS Run Command or infrastructure remediation. The AKS-managed node RG is outside the configured agent scope. Explicit Log Analytics data-connector configuration and automatic alert-to-agent incident routing are not present in the templates. Do not assume the agent automatically sees every log, accesses the private cluster, receives alerts, or fixes a fault.

## Monitoring

VM Azure Monitor Agents and their data collection rule send Syslog and performance counters to `law-srelab-swc-001`. Fresh VM heartbeats were verified. The client probe logs separate results for each endpoint; Node.js emits request/error logs. AKS Container Insights is enabled, and diagnostics are configured for Kubernetes API/audit events, Blob reads and Key Vault audit events.

Three log alert rules are deployed: dependency failure, pod failure and missing telemetry. They evaluate every five minutes over a 15-minute window, so they are not instant outage indicators. The `SRE Lab - Incident Evidence` workbook contains dependency-probe and pod-state views. No action group or automatic agent routing is configured in these templates. Actual incident alert firing and all configured log streams still require rehearsal.

The missing-heartbeat query only considers computers with records in its query window; it can miss a machine that has disappeared for the entire window. The pod alert does not check readiness comprehensively, so a pod can be `Running` but unready without this alert reliably detecting it.

Log Analytics has 30-day retention and a 1 GB/day cap. Ingestion caps can create telemetry gaps. Agent Application Insights is not application distributed tracing for the Node.js workloads. The frontend logs sanitized dependency-check summaries to stdout.

## Will A Fault Make The App Go Down?

It depends on the target. The table describes expected impact; the authoritative executable catalog and verification records are in [SCENARIOS.md](SCENARIOS.md). A degraded dashboard is different from an unavailable frontend. Deleting an arbitrary pod or adding a NetworkPolicy is not a catalog scenario.

| Fault target | Expected visible effect | Frontend availability |
|---|---|---|
| `Set-WebOutage.ps1 -Action Inject` | Web replicas saved, scaled to zero; viewer shows web unavailable and dependencies unknown | Unavailable; reset rehearsed successfully |
| Web pod crash, OOM, bad image, unschedulable configuration | Restart/backoff/pending; unavailable when no healthy web endpoint remains | Yes, if the fault removes all serving replicas |
| Web readiness failure | Pod may remain Running but becomes unready; Service loses its ready endpoint | Yes, if no other ready replica remains |
| Delete a web pod | Deployment recreates it; likely brief interruption only | Transient, not a sustained demonstration |
| Deny ingress to web with NetworkPolicy | Probe cannot reach web even if pod remains Running/Ready | Yes for blocked callers |
| Missing/wrong backend DNS record | Backend and/or client dashboard checks fail; scope depends on zone/link changed | Page stays available, status degrades |
| Blackhole or wrong next hop in client route table | Client-dependent checks fail; direct AKS-to-backend check may remain healthy | Page stays available, status degrades |
| NSG deny to backend 8081 | Backend checks fail for blocked sources; backend process may still run | Page stays available, status degrades |
| Blob private endpoint or private DNS failure | Storage dashboard check fails | Page stays available, status degrades |
| Storage/Key Vault/ARM role removal | Corresponding check fails after permission changes propagate | Page stays available, status degrades |
| Kubernetes operator RoleBinding removed | Operator cannot list pods; existing applications continue serving | No |
| Backend VM stopped or backend service unavailable | Client and backend dashboard checks fail | Page stays available, status degrades |
| Client VM stopped | Four client-dependent checks fail; direct backend check can remain healthy | Page stays available, status degrades |
| VM application data disk full or bad release config | That VM's health check fails; backend failure propagates to its callers | Page stays available, status degrades |
| CPU or memory pressure | Slowness, timeout or process termination depends on target and limits | Only if web/node capacity is affected |
| VM monitoring agent stopped | Telemetry becomes stale while the application can remain healthy | No |

A bad Deployment update is not guaranteed to cause an outage: the default rolling update can keep the previous healthy pod serving while a replacement fails. The five AKS incident scripts temporarily use Recreate and restore the full captured spec. CPU stress alone is not an outage guarantee; the operations section instead reports actual measured pressure.

### Independent Operations Observer

The loopback viewer runs `Get-OperationsSnapshot.ps1` separately from the web API collector. Using the signed-in operator's existing permissions, it reads deployment status, tests a short-lived namespace operator token with an isolated kubeconfig, reads VM power through ARM, measures backend CPU/memory/disk/AMA through VM Run Command, and queries Log Analytics for both expected hosts. No new access is granted to the web pod or browser.

Ten checks carry individual timestamps and become unknown after three minutes. A red operational summary is visible even when all six application requests succeed. Heartbeats use a left join against both expected hosts so complete host absence is detected here; the separate deployed log-alert limitation described above still applies. Collection is serialized per VM/cluster across local scripts and refreshes 30 seconds after completion.

## Show The Healthy Application Now

From the workspace root in PowerShell, use the existing scoped helpers:

```powershell
. ./scripts/Common.ps1
Assert-Lab
Invoke-LabKube -Command 'kubectl -n srelab get deployments,pods,services -o wide'
Invoke-LabKube -Command 'kubectl -n srelab exec deployment/probe -- curl -fsS --max-time 8 http://web'
Invoke-LabKube -Command 'kubectl -n srelab logs deployment/probe --tail=12'
./scripts/Test-Lab.ps1 -IncludeTelemetry
```

Expected baseline: one ready replica for each Deployment, dashboard HTML returned, six healthy API checks, probe results `status=200` for both URLs, and a passing test. These commands do not inject a fault. The final test stores evidence under ignored `.state/baseline-verification.json`.

For the localhost viewer, run `./scripts/Start-DemoViewer.ps1 -Port 8090` and open `http://127.0.0.1:8090`. Start it while web is healthy. Observations are delayed by AKS Run Command execution plus a 15-second interval. It does not grant extra Azure permissions or expose a public endpoint. See [DEMO.md](DEMO.md) for the rehearsed failure and recovery sequence.

For a browser demonstration, an operator with network access to the private API can use an authorized Kubernetes context and `kubectl -n srelab port-forward service/web 8088:80`, then open `http://localhost:8088`. That private connectivity is not provisioned for your laptop by this lab. AKS Run Command is not a persistent port-forward tunnel to your laptop.

## Intended Demonstration Sequence

1. Show a healthy request, ready workload and recent probe logs.
2. Run `./scripts/Set-WebOutage.ps1 -Action Inject` to save the replica count and stop web. Other fault scripts are still future work.
3. Show the specific failed request alongside pod state and telemetry. Distinguish availability failure from permission or observability failure.
4. Ask SRE Agent to investigate that resource and time range, after validating the necessary connector/access setup.
5. Restore the captured state using the paired reset script; allow for DNS, RBAC and telemetry propagation.
6. Repeat the same request and baseline checks to demonstrate recovery.

The deployed frontend distinguishes failed requests from missing observations. It does not query Log Analytics, trigger fault scripts from the browser, or perform agent remediation.

## Source Map And Remaining Work

- [Infrastructure and network](infra/main.bicep)
- [Kubernetes workload definitions](scripts/Initialize-Workloads.ps1)
- [VM request behavior](workload/server.js) and [bootstrap/timer](workload/bootstrap.sh)
- [Agent configuration](infra/agent.bicep) and [monitoring configuration](infra/monitoring.bicep)
- [Baseline checks](scripts/Test-Lab.ps1) and [scoped command helpers](scripts/Common.ps1)
- [Frontend API](workload/frontend/server.cjs), [dashboard](workload/frontend/index.html), [manifest generator](scripts/Get-FrontendManifest.ps1) and [deployment helper](scripts/Deploy-Frontend.ps1)
- [Private viewer](scripts/Start-DemoViewer.ps1), [web outage/reset](scripts/Set-WebOutage.ps1) and [demo guide](DEMO.md)

Remaining: inject/reset/status scripts and rehearsals for the other scenarios, agent connector/investigation validation, alert rehearsals, and shutdown/start/teardown helpers. Running resources incur costs. The agent has always-on charges even when stopped; deleting it is required to end those charges. Single-node sizing is a cost tradeoff, not a production recommendation.