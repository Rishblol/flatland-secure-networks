# PS2 · Flatland

Secure Networks Hackathon · Network segmentation and firewall design

Flatland demonstrates how network segmentation limits what a compromised workstation can reach while preserving legitimate traffic. All eight business flows passed in both layouts. The segmented firewall blocked workstation access to protected services, and router logs corroborated the blocks. [Integration report](docs/report.md)

## Problem statement

A company runs its workstation, servers, and admin jump host on one flat network. A compromised workstation can reach internal services such as the database and file server directly. The company needs to restrict that access while keeping the web application and administrative access working.

The brief calls for at least six containers or VMs: a user workstation, web server, application server, database host, file server running Samba or equivalent, and an admin jump host. In the segmented version, connect the user, DMZ, server, and management networks through a router container. Use nftables or iptables and log dropped traffic.

The brief specifies teams of three to four. This README assigns six contributors as requested. Confirm with the organizers whether all six may participate as one team.

## Proposed solution

Build a flat baseline and a segmented layout with the same six workloads, service names, and synthetic fixtures. Give each workload a zone based on its role. Route traffic between zones through a firewall that allows only the approved connections and logs denied traffic. Compare the same service paths in both layouts and verify that the destination services are healthy when an access attempt is blocked.

## System design

The flat layout places all six workloads on one internal Docker bridge. The segmented layout uses four internal macvlan networks. Each workload attaches to one zone, and the router has one interface in each zone. Neither layout publishes lab service ports to the host. [Topology diagrams](docs/diagram.md) · [Addressing and flow matrix](docs/flow-matrix.md)

| Host | Flat layout | Segmented zone |
|---|---|---|
| Workstation | Shared network | User |
| Web server | Shared network | DMZ |
| Application server | Shared network | Server |
| Database host | Shared network | Server |
| File server | Shared network | Server |
| Admin jump host | Shared network | Management |
| Router | — | One interface in each zone |

Each segmented zone has a separate `/26` within `10.149.240.0/24`. Workloads route traffic for the other zones through their local router interface. The application, database, and file server share the Server zone and communicate directly. Check for Docker and VPN subnet conflicts before starting the lab.

### Business flow matrix

The following paths are part of the lab's [service contract](docs/runbook.md#service-contract).

| ID | Source | Destination | Protocol | Expected check |
|---|---|---|---|---|
| B01 | Workstation | Web server | HTTPS, TCP 443 | Test page returns the expected content |
| B02 | Web server | Application server | HTTP, TCP 8080 | Application health endpoint returns healthy |
| B03 | Application server | Database host | PostgreSQL, TCP 5432 | Read-only fixture query returns the expected value |
| B04 | Admin jump host | Workstation | SSH, TCP 22 | Authorized lab session runs a harmless command |
| B05 | Admin jump host | Web server | SSH, TCP 22 | Authorized lab session runs a harmless command |
| B06 | Admin jump host | Application server | SSH, TCP 22 | Authorized lab session runs a harmless command |
| B07 | Admin jump host | Database host | SSH, TCP 22 | Authorized lab session runs a harmless command |
| B08 | Admin jump host | File server | SSH, TCP 22 | Authorized lab session runs a harmless command |

## Implementation

1. **Workloads and fixtures.** Both Compose layouts use shared definitions for OpenSSH, nginx HTTPS, the HTTP application health endpoint, PostgreSQL, and Samba. The lab includes a synthetic text file and a read-only database fixture. [Shared Compose services](lab/compose.services.yaml) · [Dockerfile](lab/Dockerfile)
2. **Network policy.** The segmented router loads the `nftables` rules before opening its zone interfaces to workload traffic. It allows seven approved routed business flows and established or related return traffic. B03 stays in the Server zone. The router drops other forwarded traffic and sends rate-limited drop records to NFLOG, where a listener writes them to the router's container log. [Segmented Compose overlay](lab/compose.segmented.yaml) · [Router ruleset](firewall/flatland.nft)
3. **Validation.** The business script checks B01–B08 in either layout. The workstation validator checks fixed TCP paths, destination health, fixture state, and matching router logs. Separate application checks used the lab accounts to verify SSH login, SMB share listing, and synthetic file transfer. [Business validator](scripts/check-business.sh) · [Workstation validator](scripts/check-security.sh) · [Application evidence](evidence/application-checks.json)

<a id="acceptance-checks"></a>

## Results

| Check | Flat baseline | Segmented result |
|---|---|---|
| B01–B08 · Business flows | 8 of 8 passed | 8 of 8 passed |
| S01 · Internal service ports | Workstation reached the application, PostgreSQL, and SMB ports | All three connections were blocked. Approved HTTPS still passed. |
| S02 · Workstation SSH to database | Workstation login succeeded | The workstation connection timed out with a matching firewall drop. Jump-host SSH still passed. |
| S03 · Workstation SMB share access | Workstation listed the share | The connection timed out with a matching firewall drop. The share remained healthy. |
| S04 · Synthetic SMB file copy | Copy succeeded and both SHA-256 hashes matched. The uploaded copy was removed. | The upload timed out with a matching firewall drop. The destination remained empty. |
| L01 · Firewall evidence | Connectivity and client results recorded | All four fixed TCP probes and all three application checks matched router drop records. |

The automated regression suite passed. The application checks were run individually. Hostname validation covered the declared service names in both layouts. Discovery of previously unknown hosts and outbound filtering remain untested. [Integration report and ATT&CK mapping](docs/report.md) · [Validation coverage](docs/security-validation.md)

## Contributor roles

Replace the contributor labels with names or GitHub handles at kickoff. Each owner opens a PR for their files and names the reviewer in the table.

| Contributor | Owns | Handoff | Reviewer |
|---|---|---|---|
| Person 1 · Lab setup | Flat topology, shared service definitions, fixtures, and startup and reset instructions | Stable service names, ports, and a healthy flat lab to Persons 2, 4, and 5 | Person 2 |
| Person 2 · Network design | Segmented topology, router interfaces and routing, addressing plan, diagram, and flow matrix | Zone and interface assignments plus the approved flows to Person 3 | Person 3 |
| Person 3 · Firewall | Default-deny ruleset, return-traffic handling, rule loading, and drop logging | A loaded policy and the log location to Persons 4 and 5 | Person 2 |
| Person 4 · Business validation | Business-flow script and results for B01–B08 in both layouts | A per-flow pass/fail table to Person 6 | Person 1 |
| Person 5 · Security validation | Workstation security-check script and evidence for S01–S04 and L01 | Before-and-after results and matching firewall log excerpts to Person 6 | Person 3 |
| Person 6 · Integration and demo | Clean integration run from the merged revision, acceptance evidence, report and ATT&CK mapping, demo rehearsal, and final submission | Repository link or ZIP tied to the tested commit, with a complete results table and a 5–7 minute demo for judging | Person 4 |

When a service port, name, or zone changes, update the flow matrix and notify the firewall and validation owners in the PR.

### Person 6 · Integration checklist

1. Start from a clean lab at the merged commit. Record the commit SHA, run commands, and timestamps. Run the business and security validation suites in both layouts and capture the segmented firewall logs.
2. Consolidate B01–B08, S01–S04, and L01 into one results table with expected and observed outcomes and links to evidence. Verify that each claimed firewall block has a passing flat baseline, a service health check, and a matching drop log. Record unresolved failures and rerun affected checks after fixes.
3. Complete the report and link each ATT&CK mapping to the matching test evidence. Check that the tested revision includes the diagram, flow matrix, ruleset, scripts, runbook, and results.
4. Rehearse the 5–7 minute demo with the tested revision. Walk through one legitimate flow that still works and one denied flow with its corresponding log. Submit the repository link or ZIP for that revision.

## Five-hour plan

| Time | Work | Exit condition |
|---|---|---|
| 0:00–0:45 | Person 1 brings up the flat lab. Persons 2 and 3 agree on zones, ports, and router interfaces. Persons 4 and 5 agree on cases and expected results. Person 6 sets up the results table. | The flat lab starts and service names and ports are agreed. |
| 0:45–2:45 | Persons 4 and 5 run the baseline as soon as services are healthy. Persons 2 and 3 build the segmented topology and router policy in parallel. Person 1 keeps the fixtures consistent, and Person 6 drafts the report. | Baseline evidence is saved and the segmented lab is ready for validation. |
| 2:45–4:15 | Repeat all checks on the segmented lab. Trace failures to service health, routing, or policy. Rerun both suites after fixes. | All required business flows pass, all required workstation checks are blocked, and the drop logs support the results. |
| 4:15–4:45 | Person 6 leads a clean run and demo rehearsal. Owners review their evidence and finalize the diagram, matrix, ruleset, scripts, and mapping. | A teammate can reproduce the checks from the runbook and the demo fits in 5–7 minutes. |
| 4:45–5:00 | Freeze changes and submit the repository link or ZIP. | Submission points to the revision used for the demo. |

## Repository layout

| Path | Contents |
|---|---|
| `README.md` | Problem statement, design, implementation, results, and team plan |
| `lab/` | Flat and segmented Compose definitions, service configs, and synthetic fixtures |
| `firewall/flatland.nft` | Router firewall policy |
| `scripts/check-business.sh` | Business-flow checks |
| `scripts/check-security.sh` | Workstation security checks for the isolated lab |
| `docs/diagram.md` | Flat and segmented topology diagrams |
| `docs/flow-matrix.md` | Addresses, ports, and approved flows |
| `docs/runbook.md` | Prerequisites, startup, validation, reset, and teardown commands |
| `docs/report.md` | Results, limitations, and ATT&CK mapping |
| `evidence/` | Baseline and segmented test outputs, application checks, and firewall logs |
| `demo/` | Dashboard for topology, recorded evidence, and live Docker health |

Use the [runbook](docs/runbook.md) for the exact launch and teardown commands. Keep fixture data synthetic and credentials disposable. Record the revision, topology, test case ID, and expected and observed outcomes with the evidence.

## ATT&CK mapping

The [integration report](docs/report.md#attck-mapping) maps the observed lab behavior to ATT&CK and D3FEND. Coverage varies by technique.

| Technique | Lab evidence |
|---|---|
| T1046 · Network Service Discovery | Visibility of designated internal service ports from the workstation |
| T1021.002 · SMB/Windows Admin Shares or T1021.004 · SSH | Remote-service evidence for the protocol and behavior demonstrated |
| T1570 · Lateral Tool Transfer | Transfer of the synthetic fixture between lab hosts |
| T1018 · Remote System Discovery | Known lab hostnames resolved in both layouts. Discovery of previously unknown hosts remains untested. |

The brief also lists D3FEND Network Isolation, Inbound Traffic Filtering, and Outbound Traffic Filtering, plus ATT&CK mitigations M1030 (Network Segmentation) and M1037 (Filter Network Traffic).

## Demo and submission

Start both layouts from the repository root to prepare the live demo.

```console
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml up --build --wait
docker compose -f lab/compose.services.yaml -f lab/compose.segmented.yaml up --build --wait
python demo/serve.py
```

Open the [local dashboard](http://127.0.0.1:8765/) and switch between **Flat** and **Segmented**. Container readiness updates automatically. Select a traffic result for recorded evidence, or expand **Live runtime** for the current router log. The recorded evidence remains available when Docker is offline.

1. **One minute** · Show the diagram and explain which business paths need to stay open.
2. **One to two minutes** · Show the flat baseline and explain what the workstation could reach.
3. **Two minutes** · Run the segmented checks and show allowed flows, blocked access, and drop logs.
4. **One minute** · Point judges to the ruleset, evidence, and ATT&CK mapping.

Submit the network diagram, flow matrix, firewall ruleset, both scripts, baseline and segmented results, and ATT&CK mapping with the repository or ZIP. If the core checks are complete early, the brief lists database host microsegmentation, egress filtering, and management-port rate limiting as optional stretch work.
