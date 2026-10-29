# SRE Day Lab: Simple Script Guide

**Public shop:** https://srelab-shop-2d6ikhr5ewo6o.swedencentral.cloudapp.azure.com/ (no localhost required). Fieldnote runs on AKS and the two Azure VMs, with private Blob images, Key Vault-backed simulated checkout and persisted orders. Public HTTPS, all four images and checkout/lookup were verified on 2026-09-22. Blob endpoint, Vault endpoint and disk-full shop outages/recovery were also verified. See [SHOP.md](SHOP.md) for access, deployment, costs and remaining scenario limits. The operator health dashboard remains private.

This guide explains the files and the order to run them. **The lab is already deployed: normally use "Every Demo Session", not "First-Time Setup".**

For all 28 DNS/network/permission/VM/AKS/resource/monitoring faults, use [the scenario catalog and execution guide](SCENARIOS.md). Each has its own script with Inject, Status, Verify and Reset. The dashboard separates six application checks from ten operations/observability checks, so an operator permission failure or telemetry gap is visible even while applications remain healthy.

For the recommended presentation order, follow [the phased test runbook](TEST-RUNBOOK.md): Blob images, Key Vault checkout, then every remaining scenario, with commands, expected impact, alert expectations, SRE prompts and recovery checks.

Run commands in **PowerShell 7 from the workspace root**, the folder containing this README. You need Node.js and Azure CLI installed, and Azure CLI signed in with your authorized lab account. Initial deployment also needs Bicep support in Azure CLI and `ssh-keygen`.

The scripts target subscription `15ba7e94-568d-4ba9-bb5d-29ed107ac109` and resource group `rg-srelab-swedencentral-001` in Sweden Central. Their shared helper fixes this scope; switching the CLI default subscription does not retarget the lab.

## Every Demo Session

Use two PowerShell terminals. Stop if a command fails; resolve the failure before continuing.

### Terminal 1: Check And Open

1. Check the web workload and whether a previous demo saved recovery state:

   ```powershell
   ./scripts/Set-WebOutage.ps1 -Action Status
   ```

   If it reports `Saved recovery state: True`, restore it before proceeding:

   ```powershell
   ./scripts/Set-WebOutage.ps1 -Action Reset
   ```

   Do not run Reset routinely when there is no saved state. If web is unhealthy without saved state, investigate rather than injecting another fault.

2. Verify the healthy lab, including recent VM telemetry:

   ```powershell
   ./scripts/Test-Lab.ps1 -IncludeTelemetry
   ```

3. Open the public shop URL above. For the optional operator dashboard, start the local viewer while the AKS web workload is healthy:

   ```powershell
   ./scripts/Start-DemoViewer.ps1 -Port 8090
   ```

   Keep this terminal running only when using the private dashboard at **http://127.0.0.1:8090/health**. Wait for **Applications healthy**, **6 / 6**, and **Operations healthy**. If a viewer is already running, reuse it; do not start a second copy on the same port. The public storefront does not require this viewer.

### Terminal 2: Fail And Recover

4. Stop only the AKS web workload:

   ```powershell
   ./scripts/Set-WebOutage.ps1 -Action Inject
   ```

   Wait for the browser to show **Web application unavailable**. The other checks become **Unknown**, because web cannot report them. Allow tens of seconds for the relay to refresh.

5. Restore the saved replica count:

   ```powershell
   ./scripts/Set-WebOutage.ps1 -Action Reset
   ```

   Wait for the browser to return to **Applications healthy** and **6 / 6**. To repeat the demonstration, repeat steps 4 and 5; do not redeploy.

6. Verify the recovered lab before finishing:

   ```powershell
   ./scripts/Test-Lab.ps1 -IncludeTelemetry
   ```

7. After recovery, press **Ctrl+C** in Terminal 1 to stop the viewer and its repeated Azure requests. This does **not** stop or delete Azure resources, which continue to incur costs.

**Safety:** Inject saves recovery information before changing replicas. If injection fails after saving state, attempt Reset. If Reset fails, preserve the state and resolve the error before retrying. Never delete recovery state to bypass a safeguard or deploy workloads during an active outage. `-WhatIf` previews the scaling action but still performs prerequisite reads.

## First-Time Setup

Use this sequence only for a new lab deployment, or deliberately applying reviewed infrastructure changes. These commands create or update billable resources and require deployment/RBAC-assignment permissions.

```powershell
# 1. Check local code and script syntax.
./tests/Validate-Local.ps1

# 2. Create/update the Azure infrastructure.
./scripts/Deploy-Lab.ps1

# 3. Wait for VM bootstrap and deploy the Kubernetes workloads.
./scripts/Initialize-Workloads.ps1

# 4. Verify the complete healthy baseline.
./scripts/Test-Lab.ps1 -IncludeTelemetry

# 5. Open the demo viewer and keep this terminal running.
./scripts/Start-DemoViewer.ps1 -Port 8090
```

Initialization already deploys the frontend, so you do not also need to run the frontend-only deployment script. Fresh monitoring data may take time to arrive on a new deployment; investigate a missing-heartbeat result and rerun verification once telemetry is flowing.

Optional infrastructure validation: `./scripts/Deploy-Lab.ps1 -ValidateOnly` stops before the resource deployment, but **is not completely read-only**: it can create the resource group, generate an SSH key and write local parameters.

For existing VMs, the deployment script omits immutable bootstrap `customData`; new VMs still receive the bootstrap. Apply VM application changes with `./scripts/Update-VmWorkload.ps1`, not an infrastructure redeployment. The script also discovers and retains existing AKS and private-endpoint subnet NSG associations without managing their rules. Direct Bicep deployments must supply equivalent `existingVmNames`, `aksSubnetNsgId` and `privateEndpointSubnetNsgId` parameters for an existing lab.

## After Changing Frontend Code

With no active outage, run:

```powershell
./tests/Validate-Local.ps1
./scripts/Deploy-Frontend.ps1
./scripts/Test-Lab.ps1 -IncludeTelemetry
```

Then stop and restart the viewer to fetch the updated AKS HTML. Frontend redeployment assumes the cluster, `srelab` namespace and probe already exist. It does not create the full lab. Use `./scripts/Update-VmWorkload.ps1` for VM application source updates; the frontend deployment script does not update VM code. Both update paths refuse active incidents.

## Files In Each Folder

### scripts: Operator Commands And Helpers

| File | What it does | When to use it |
|---|---|---|
| [Deploy-Lab.ps1](scripts/Deploy-Lab.ps1) | Validates the Bicep template, runs what-if, deploys Azure infrastructure and saves deployment outputs. | Initial setup or deliberate infrastructure updates; not every demo. |
| [Initialize-Workloads.ps1](scripts/Initialize-Workloads.ps1) | Checks VM bootstrap; applies the AKS namespace, operator read role, probe and web frontend; waits for rollouts. | After infrastructure deployment; not a routine reset. |
| [Test-Lab.ps1](scripts/Test-Lab.ps1) | Checks VM services, data mount, DNS, dependencies, six frontend checks, Kubernetes operator access and agent provisioning. `-IncludeTelemetry` also checks VM heartbeats. | Before and after a demo, or after changes. Does not verify an agent investigation. |
| [Start-DemoViewer.ps1](scripts/Start-DemoViewer.ps1) | Fetches the real AKS HTML, caches it locally and starts the loopback viewer. | Start while web is healthy; leave running during the demo. |
| [Set-WebOutage.ps1](scripts/Set-WebOutage.ps1) | `Status`: inspect web. `Inject`: save replicas and scale to zero. `Reset`: restore replicas, wait for rollout and check health. | Web scale-to-zero demonstration. |
| [Deploy-Frontend.ps1](scripts/Deploy-Frontend.ps1) | Applies just the frontend ConfigMap, Deployment and Service; waits for rollout. | After changing frontend source. |
| [Get-DemoSnapshot.ps1](scripts/Get-DemoSnapshot.ps1) | Gets a real status snapshot through AKS Run Command and the probe; `-Page` returns the AKS HTML instead. | Called automatically by the viewer; optional manual diagnosis. |
| [Get-FrontendManifest.ps1](scripts/Get-FrontendManifest.ps1) | Builds Kubernetes objects from the frontend source, including a content-hashed ConfigMap. Does not deploy them itself. | Called automatically by initialization and frontend deployment. |
| [Common.ps1](scripts/Common.ps1) | Shared lab scope, Azure CLI wrapper, resource checks, state writing and VM/AKS Run Command helpers. | Loaded automatically by other scripts; you do not need to run it first. |
| [Invoke-LabScenario.ps1](scripts/Invoke-LabScenario.ps1) | Shared Inject/Status/Verify/Reset lifecycle, incident lock and saved-state recovery. | Called by every individual script listed in [SCENARIOS.md](SCENARIOS.md). |
| [ScenarioCatalog.ps1](scripts/ScenarioCatalog.ps1) | Allowlisted 28 fault definitions and target checks. | Loaded automatically; not a deployment script. |
| [ScenarioEngine.ps1](scripts/ScenarioEngine.ps1) | Read-only original-state capture and scoped mutations/restoration. | Loaded automatically. |
| [Inspect-Scenario.ps1](scripts/Inspect-Scenario.ps1) | Read-only Azure/Kubernetes/guest evidence appropriate to the selected scenario. | Called by Status; also accepts `-Scenario Name` directly. |
| [Test-Scenario.ps1](scripts/Test-Scenario.ps1) | Requires an actual failure or recovery observation and saves evidence. | Called by Verify and Reset. |
| [Get-OperationsSnapshot.ps1](scripts/Get-OperationsSnapshot.ps1) | Ten real operational checks, including isolated operator token authorization and expected-host heartbeat freshness. | Called automatically by the local viewer. |
| [Rehearse-Scenarios.ps1](scripts/Rehearse-Scenarios.ps1) | Sequential inject/verify/reset with bounded verification attempts and recovery in finally. | Rehearse a selected list, never concurrent faults. |
| [Update-VmWorkload.ps1](scripts/Update-VmWorkload.ps1) | Updates and syntax-checks the VM application on both lab VMs. | After VM source changes, with no active incident. |

### infra: Infrastructure Templates

These are Bicep source files, not scripts to execute individually. The deployment script starts with the main template, which calls the modules.

| File | Purpose |
|---|---|
| [main.bicep](infra/main.bicep) | Main definition connecting networking, AKS, VMs, private services, identities, monitoring and agent resources. |
| [vm.bicep](infra/vm.bicep) | VM and supporting resources, bootstrap configuration and monitoring extension. |
| [dns-links.bicep](infra/dns-links.bicep) | Links private DNS zones to the lab VNets. |
| [endpoints.bicep](infra/endpoints.bicep) | Blob Storage and Key Vault private endpoints and DNS zone associations. |
| [monitoring.bicep](infra/monitoring.bicep) | Diagnostic settings, log alerts and the incident-evidence workbook. |
| [agent.bicep](infra/agent.bicep) | SRE Agent, its identity/access and Application Insights integration. |

### workload: Application Code

| File | Where it runs and what it does |
|---|---|
| [bootstrap.sh](workload/bootstrap.sh) | Runs during VM provisioning: installs/configures the VM application, isolated data mount, systemd service and client check timer. Do not run on your Windows laptop. |
| [server.js](workload/server.js) | VM Node.js application: health/config/disk checks and managed-identity requests to Storage, Key Vault and ARM. |
| [frontend/server.cjs](workload/frontend/server.cjs) | AKS Node.js application: serves the dashboard, checks dependencies and exposes status and health endpoints. |
| [frontend/index.html](workload/frontend/index.html) | Dashboard displayed in the browser: health rows, latency, timestamps and history. |
| [frontend/viewer.cjs](workload/frontend/viewer.cjs) | Local Node.js relay: serves cached AKS HTML and retrieves snapshots through PowerShell. Started by the viewer script. |

### tests: Local Validation

| File | Purpose |
|---|---|
| [Validate-Local.ps1](tests/Validate-Local.ps1) | Parses PowerShell, checks Node syntax and runs frontend behavior tests. Does not deploy resources or prove live Azure health. |
| [frontend.test.cjs](tests/frontend.test.cjs) | Five automated tests for frontend parsing, healthy/failed checks, safe output, concurrent collection and API behavior. Called by local validation. |
| [operations.test.cjs](tests/operations.test.cjs) | Independent operational failure and stale/unknown UI behavior. |
| [ScenarioCatalog.Tests.ps1](tests/ScenarioCatalog.Tests.ps1) | All 28 definitions, wrapper routing and allowlist checks. |
| [ScenarioEngine.Tests.ps1](tests/ScenarioEngine.Tests.ps1) | Read-only capture, service/stress preflight, NSG restoration and UTC timestamp regression checks. |

### Other Folders And Documents

| Location | Purpose |
|---|---|
| `.state/` | Generated local files: deployment parameters/output, Kubernetes manifests, cached HTML, baseline evidence and active outage recovery state. Not source code. Do not delete while an outage is active or publish these files. |
| [memory-bank/tasks/TASK001-sre-lab.md](memory-bank/tasks/TASK001-sre-lab.md) and [task index](memory-bank/tasks/_index.md) | Project progress and remaining work; nothing to execute. |
| [.github/modernize/assessment/engines/facts/architecture-diagram.md](.github/modernize/assessment/engines/facts/architecture-diagram.md) | Architecture diagrams and component inventory; not an execution script or deployment pipeline. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Full resource, network, application and identity relationships. |
| [DEMO.md](DEMO.md) | Detailed web-outage demonstration, verification results and viewer behavior. |
| [.gitignore](.gitignore) | Keeps generated/local artifacts out of version control. |

## Important Limits

- All 28 additional scenarios are implemented. Live rehearsal evidence is recorded separately from local test results; see [SCENARIOS.md](SCENARIOS.md). Check `.state/active-incident.json` as well as the older web recovery record before a session, and reset the named incident first.
- The shop has a public HTTPS gateway; operations routes, VM services, Blob/Vault and the AKS API remain private. The optional `localhost:8090/health` dashboard is a local relay using your Azure CLI identity and AKS Run Command access; the browser does not receive Azure tokens. See SHOP.md for ingress removal and ongoing gateway/disk costs.
- The viewer's delayed polling is a demo workaround. [Microsoft documents Run Command as unsuitable for programmatic access](https://learn.microsoft.com/en-us/azure/aks/access-private-cluster#limitations-and-considerations); use proper private connectivity or secured ingress for a durable application access path.
- No script currently automates SRE Agent investigation or remediation. Agent provisioning checks do not prove it can investigate an incident.
- There is no complete stop/start/cleanup script yet. Stopping web or the local viewer does not stop Azure billing. SRE Agent always-on charges persist while the agent is stopped; deletion is required to end those charges.