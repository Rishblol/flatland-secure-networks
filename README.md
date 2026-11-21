# PS2 · Flatland

Secure Networks Hackathon · Network segmentation and firewall design

**Status:** Planning. The topology, file paths, and checks below are proposed. The team will fill in actual results after running the lab.

## Problem statement

A company runs its workstation and servers on one flat network. A compromised workstation can reach services it has no business accessing. Build the flat network, capture a baseline, then split it into security zones and enforce a default-deny policy. The demo must show that unauthorized paths are blocked while legitimate business traffic still works.

The brief calls for at least six containers or VMs: a user workstation, web server, application server, database host, file server running Samba or equivalent, and an admin jump host. In the segmented version, connect the user, DMZ, server, and management networks through a router container. Use nftables or iptables and log dropped traffic.

The brief specifies teams of three to four. This README assigns six contributors as requested. Confirm with the organizers whether all six may participate as one team.

## Lab design

Use Docker Compose for reproducible environments and nftables for the router policy. Use the same service images, service names, and test fixtures in both layouts. Keep the workloads on isolated lab networks and run validation only against team-owned lab services.

| Host | Flat layout | Segmented zone |
|---|---|---|
| Workstation | Shared network | User |
| Web server | Shared network | DMZ |
| Application server | Shared network | Server |
| Database host | Shared network | Server |
| File server | Shared network | Server |
| Admin jump host | Shared network | Management |
| Router | — | One interface in each zone |

Assign one non-overlapping subnet per zone. Before implementation, record subnet ranges, gateway addresses, interface names, and how each host reaches other zones. Check for Docker and VPN subnet conflicts. Verify that traffic between zones goes through the router and that host port publishing or extra network attachments do not bypass it. The application, database, and file server share a zone in this plan. Their same-zone traffic does not traverse the router.

### Proposed business flow matrix

Confirm the actual service ports with the lab owner before implementing the firewall. Add a separate test result for each jump-host destination.

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

The firewall owner should allow the approved inter-zone flows and their return traffic, then log and drop other forwarded traffic. Keep any required infrastructure flows explicit in the matrix. Treat the matrix as the source of truth for reviews and tests.

## Acceptance checks

Run the same checks from the same source roles in both layouts. Record the expected result, observed result, timestamp, and evidence for every test. A service that was already down in the flat layout cannot demonstrate that the firewall blocked it.

| Check | Flat baseline | Segmented result |
|---|---|---|
| B01–B08 · Business flows | All pass | All still pass |
| S01 · Workstation visibility of designated internal service ports | Internal ports in scope are reachable | Internal ports in scope are blocked. The permitted HTTPS service remains reachable. |
| S02 · Workstation-to-database-host SSH | Lab SSH access is demonstrated | Workstation access is blocked while admin SSH to the host still works |
| S03 · Workstation-to-file-server SMB | Lab SMB access is demonstrated | Workstation access is blocked |
| S04 · Workstation file copy to a second lab host | A synthetic fixture is successfully copied using the designated lab service | The same copy fails and the fixture is absent at the destination |
| L01 · Firewall evidence | Baseline results captured | Drop logs corroborate the denied cross-zone checks |

The brief expects two reproducible scripts, one for legitimate traffic and one for the workstation security checks. Use disposable fixtures. Record which destination and service S04 uses, ensure that path is outside the allowlist, and reset the destination fixture between runs. For a blocked result, confirm the destination service is healthy through an authorized path or a local health check.

## Contributor roles

Replace the contributor labels with names or GitHub handles at kickoff. Each owner opens a PR for their files and names the reviewer in the table.

| Contributor | Owns | Handoff | Reviewer |
|---|---|---|---|
| Person 1 · Lab setup | Flat topology, shared service definitions, fixtures, and startup and reset instructions | Stable service names, ports, and a healthy flat lab to Persons 2, 4, and 5 | Person 2 |
| Person 2 · Network design | Segmented topology, router interfaces and routing, addressing plan, diagram, and flow matrix | Zone and interface assignments plus the approved flows to Person 3 | Person 3 |
| Person 3 · Firewall | Default-deny ruleset, return-traffic handling, rule loading, and drop logging | A loaded policy and the log location to Persons 4 and 5 | Person 2 |
| Person 4 · Business validation | Business-flow script and results for B01–B08 in both layouts | A per-flow pass/fail table to Person 6 | Person 1 |
| Person 5 · Security validation | Workstation security-check script and evidence for S01–S04 and L01 | Before-and-after results and matching firewall log excerpts to Person 6 | Person 3 |
| Person 6 · Integration and demo | Integration run, submission checklist, ATT&CK mapping, report, and demo | Verified repository or ZIP and a rehearsed demo for judging | Person 4 |

When a service port, name, or zone changes, update the flow matrix and notify the firewall and validation owners in the PR. Person 6 coordinates the final run from the merged revision and records the commit used for the evidence.

## Five-hour plan

| Time | Work | Exit condition |
|---|---|---|
| 0:00–0:45 | Person 1 brings up the flat lab. Persons 2 and 3 agree on zones, ports, and router interfaces. Persons 4 and 5 agree on cases and expected results. Person 6 sets up the results table. | The flat lab starts and service names and ports are agreed. |
| 0:45–2:45 | Persons 4 and 5 run the baseline as soon as services are healthy. Persons 2 and 3 build the segmented topology and router policy in parallel. Person 1 keeps the fixtures consistent, and Person 6 drafts the report. | Baseline evidence is saved and the segmented lab is ready for validation. |
| 2:45–4:15 | Repeat all checks on the segmented lab. Trace failures to service health, routing, or policy. Rerun both suites after fixes. | All required business flows pass, all required workstation checks are blocked, and the drop logs support the results. |
| 4:15–4:45 | Person 6 leads a clean run and demo rehearsal. Owners review their evidence and finalize the diagram, matrix, ruleset, scripts, and mapping. | A teammate can reproduce the checks from the runbook and the demo fits in 5–7 minutes. |
| 4:45–5:00 | Freeze changes and submit the repository link or ZIP. | Submission points to the revision used for the demo. |

## Proposed repository layout

| Path | Contents |
|---|---|
| `README.md` | Problem statement, team plan, and acceptance criteria |
| `lab/` | Flat and segmented Compose definitions, service configs, and synthetic fixtures |
| `firewall/flatland.nft` | Router firewall policy |
| `scripts/check-business.sh` | Business-flow checks |
| `scripts/check-security.sh` | Workstation security checks for the isolated lab |
| `docs/diagram.md` | Flat and segmented topology diagrams |
| `docs/flow-matrix.md` | Addresses, ports, and approved flows |
| `docs/runbook.md` | Prerequisites, startup, validation, reset, and teardown commands |
| `docs/report.md` | Results, limitations, and ATT&CK mapping |
| `evidence/` | Baseline and segmented test outputs and relevant firewall logs |

The lab owner should add the exact launch and teardown commands to the runbook once the topology is implemented. Keep fixture data synthetic and credentials disposable. Record the revision, topology, test case ID, and expected and observed outcomes with the evidence.

## ATT&CK mapping

Use the IDs listed in the brief and tie each mapping to evidence from the lab.

| Technique | Lab evidence |
|---|---|
| T1046 · Network Service Discovery | Visibility of designated internal service ports from the workstation |
| T1021.002 · SMB/Windows Admin Shares or T1021.004 · SSH | Remote-service evidence for the protocol and behavior demonstrated |
| T1570 · Lateral Tool Transfer | Transfer of the synthetic fixture between lab hosts |
| T1018 · Remote System Discovery | Evidence of internal host discovery where demonstrated |

The brief also lists D3FEND Network Isolation, Inbound Traffic Filtering, and Outbound Traffic Filtering, plus ATT&CK mitigations M1030 (Network Segmentation) and M1037 (Filter Network Traffic).

## Demo and submission

1. **One minute** · Show the diagram and explain which business paths need to stay open.
2. **One to two minutes** · Show the flat baseline and explain what the workstation could reach.
3. **Two minutes** · Run the segmented checks and show allowed flows, blocked access, and drop logs.
4. **One minute** · Point judges to the ruleset, evidence, and ATT&CK mapping.

Submit the network diagram, flow matrix, firewall ruleset, both scripts, baseline and segmented results, and ATT&CK mapping with the repository or ZIP. If the core checks are complete early, the brief lists database host microsegmentation, egress filtering, and management-port rate limiting as optional stretch work.

*Source: Secure Networks Hackathon brief, PS2 “Flatland” and event format.*
