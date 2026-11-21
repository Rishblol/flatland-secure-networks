# Flatland integration report

The flat lab puts six workloads on one shared Docker network. The segmented lab places the same workloads in four zones and routes cross-zone traffic through a default-deny `nftables` policy. The application, database, and file server share the Server zone, so the application-to-database flow takes a direct path.

[Topology diagrams](diagram.md) · [Flow matrix](flow-matrix.md) · [Firewall policy](../firewall/flatland.nft) · [Runbook](runbook.md)

## Acceptance results

The Person 6 run used `44138d5511411cb4b2f58d657c122f018c2d5932` on 21 November 2026 with Docker Engine 29.10.0 (Linux AMD64 on Ubuntu WSL 2) and Compose 5.8.0. Both layouts built and started in fresh Compose projects. They resolved to internal networks with zero published host ports. The Docker-free regression suite, Compose configuration checks, and router policy syntax check passed.

The table reflects the fresh integration run. Each raw log records timestamps, health checks, expected and observed results, and the tested revision. The segmented log includes a direct route for B03, a firewall allow-rule hit for each of the other seven business flows, and matching SYN drops for all four distinct denied connections. [Integration flat log](../evidence/integration-flat.log) · [Integration segmented log](../evidence/integration-segmented.log)

| Check | Expected | Flat observed | Segmented observed |
|---|---|---|---|
| B01 · Workstation → web | HTTPS returns the test page | Pass | Pass |
| B02 · Web → app | HTTP health check returns `healthy` | Pass | Pass |
| B03 · App → database | Read-only query returns `flatland-db-ok` | Pass | Pass, direct within Server |
| B04 · Jump → workstation | Authorized SSH returns `lab` | Pass | Pass |
| B05 · Jump → web | Authorized SSH returns `lab` | Pass | Pass |
| B06 · Jump → app | Authorized SSH returns `lab` | Pass | Pass |
| B07 · Jump → database | Authorized SSH returns `lab` | Pass | Pass |
| B08 · Jump → file | Authorized SSH returns `lab` | Pass | Pass |
| S01 · Workstation visibility | App, PostgreSQL, and SMB ports connect in flat and are blocked in segmented. B01 remains available. | All three TCP connections succeeded | All three timed out, each with a matching router drop. B01 passed. |
| S02 · Workstation → database SSH | Workstation SSH access works in flat and is blocked in segmented. B07 still passes. | TCP connected. Workstation SSH authentication unverified. | TCP timed out with a matching drop. B07 passed. |
| S03 · Workstation → file SMB | Workstation share access works in flat and is blocked in segmented. | TCP connected and local share was healthy. Workstation share access unverified. | TCP timed out with a matching drop. Local share stayed healthy. |
| S04 · Synthetic file copy | Copy succeeds in flat and is blocked in segmented | End-to-end copy not run. Source fixture available and destination absent before and after. | End-to-end copy not run. Source fixture available and destination absent before and after. |
| L01 · Firewall evidence | Each of the four distinct segmented TCP denials has a matching drop log | Baseline connectivity recorded | Four of four matched. S03 shares S01's SMB observation. |

The earlier business run used `71dce1f` and the earlier security run used `d75f7f5`. [Business results](../evidence/business-results.md) · [Security results](../evidence/security-results.md) · [Validation coverage](security-validation.md)

S02 and S03 establish transport reachability. Workstation SSH authentication and workstation SMB share interaction remain unverified. S04's fixture checks establish file state only. The policy applies at the inter-zone router. Traffic among hosts within the Server zone bypasses that router.

## ATT&CK mapping

| Technique | Evidence and coverage |
|---|---|
| [T1046 · Network Service Discovery](https://attack.mitre.org/techniques/T1046/) | S01 represents visibility of three known service ports in the flat layout. Their segmented timeouts and L01 drops show the effect of filtering those paths. |
| [T1021.004 · SSH](https://attack.mitre.org/techniques/T1021/004/) | S02 measures workstation access to the SSH transport. B07 demonstrates an authorized session from Management. |
| [T1021.002 · SMB/Windows Admin Shares](https://attack.mitre.org/techniques/T1021/002/) | S03 measures SMB transport and confirms the share is healthy locally. It provides context for SMB-based remote access. |
| [T1570 · Lateral Tool Transfer](https://attack.mitre.org/techniques/T1570/) | S04 is the planned coverage. The fixture observations and S03 transport denial leave the transfer itself unverified. |
| [T1018 · Remote System Discovery](https://attack.mitre.org/techniques/T1018/) | Open. The validator uses known lab endpoints. |

[M1030 · Network Segmentation](https://attack.mitre.org/mitigations/M1030/) corresponds to the four zones. [M1037 · Filter Network Traffic](https://attack.mitre.org/mitigations/M1037/) corresponds to the cross-zone allowlist, default drop, and drop logging.

[D3-NI · Network Isolation](https://d3fend.mitre.org/tactic/d3f%3AIsolate/) corresponds to the isolated lab networks and the zoned topology. The User-to-Server denials illustrate [D3-ITF · Inbound Traffic Filtering](https://d3fend.mitre.org/technique/d3f%3AInboundTrafficFiltering/) at the Server boundary. [D3-OTF · Outbound Traffic Filtering](https://d3fend.mitre.org/technique/d3f%3AOutboundTrafficFiltering/) is outside the recorded test coverage.

## Six-minute demo

Prepare both layouts using the [runbook](runbook.md) and keep the paired validation logs available.

1. **0:00–1:00** · Show the flat topology and the four segmented zones. Identify the workstation, public-facing web service, internal services, and jump host.
2. **1:00–2:00** · Use the flat run to show B01 succeeds and the workstation can also reach the application port directly.
3. **2:00–4:00** · In the segmented results, show B01 and B07 still succeed. Compare S01-app with the flat result and show its matching router line and healthy destination. Explain why B03 takes the direct route.
4. **4:00–5:00** · Point to the approved flows and default drop in the router policy. Show the L01 result and how the timestamps and connection fields link it to the denied checks.
5. **5:00–6:00** · Walk through the ATT&CK mapping, including the open S04 transfer and application-level gaps. Point judges to the report, revision, and raw evidence.

## Submission handoff

The final branch packages this report with the topology diagram, flow matrix, firewall ruleset, both validators, and the raw evidence. The integration logs identify the revision used to run the lab. The handoff commit adds the report and the new evidence while preserving the tested lab, firewall, and validation files. Confirm the team-size exception with the organizers before submission. [Diagram](diagram.md) · [Flow matrix](flow-matrix.md) · [Ruleset](../firewall/flatland.nft) · [Business validator](../scripts/check-business.sh) · [Security validator](../scripts/check-security.sh) · [Evidence](../evidence/)
