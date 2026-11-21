# Addressing and flow matrix

## Segmented addressing

The lab uses four non-overlapping IPv4 subnets within `10.149.240.0/24`. Each workload has one interface named `eth0`, a connected `/26` route, and a route to `10.149.240.0/24` via the router interface in its zone. The more specific connected route handles traffic within the zone. The router uses its four connected routes. Neither the workloads nor the router need a default route.

| Zone | Compose network | Subnet | Docker IPAM reservation | Router interface and next hop | Workloads |
|---|---|---|---|---|---|
| User | `user` | `10.149.240.0/26` | `10.149.240.1` | `zone-user` · `10.149.240.2` | `workstation` · `10.149.240.10` |
| DMZ | `dmz` | `10.149.240.64/26` | `10.149.240.65` | `zone-dmz` · `10.149.240.66` | `web` · `10.149.240.74` |
| Server | `server` | `10.149.240.128/26` | `10.149.240.129` | `zone-server` · `10.149.240.130` | `app` · `10.149.240.138`, `database` · `10.149.240.139`, `file` · `10.149.240.140` |
| Management | `management` | `10.149.240.192/26` | `10.149.240.193` | `zone-mgmt` · `10.149.240.194` | `jump` · `10.149.240.202` |

The IPAM column lists reserved addresses that Compose records as gateways. Workloads route through the router next hops in the following column. Compose adds the six workload aliases to `/etc/hosts` in the segmented layout, so the same service names work in flat and segmented checks. Name lookup needs no inter-zone DNS rule.

## Business flows

The [service contract](runbook.md#service-contract) supplies these ports and expected results. Each routed flow maps to a rule with the corresponding ID in [flatland.nft](../firewall/flatland.nft).

| ID | Source | Destination | TCP port | Segmented path | Expected result |
|---|---|---|---|---|---|
| B01 | `workstation` | `web` | 443 HTTPS | User → DMZ | `/` contains `Flatland demo page` |
| B02 | `web` | `app` | 8080 HTTP | DMZ → Server | `/health` returns `healthy` |
| B03 | `app` | `database` | 5432 PostgreSQL | Direct within Server | Fixture query returns `flatland-db-ok` |
| B04 | `jump` | `workstation` | 22 SSH | Management → User | `id -un` returns `lab` |
| B05 | `jump` | `web` | 22 SSH | Management → DMZ | `id -un` returns `lab` |
| B06 | `jump` | `app` | 22 SSH | Management → Server | `id -un` returns `lab` |
| B07 | `jump` | `database` | 22 SSH | Management → Server | `id -un` returns `lab` |
| B08 | `jump` | `file` | 22 SSH | Management → Server | `id -un` returns `lab` |

The router allows new TCP connections for B01, B02, and B04–B08, plus tracked established and related IPv4 traffic. All three server-zone hosts can communicate directly within that zone. There are no additional inter-zone application or infrastructure allowances.

## Denied paths for validation

| ID | Source | Destination | TCP port | Expected result after segmentation |
|---|---|---|---|---|
| S01 | `workstation` | `app`, `database`, `file` | 8080, 5432, 445 respectively | Each connection is dropped. B01 remains reachable. |
| S02 | `workstation` | `database` | 22 | Connection is dropped. B07 still works. |
| S03 | `workstation` | `file` | 445 | Connection to SMB share `transfer` is dropped. |
| S04 | `workstation` | `file` | 445 | SMB copy of `/fixtures/transfer.txt` fails and `/srv/transfer/transfer.txt` stays absent after reset. |
| L01 | `router` | NFLOG group 10 | — | A rate-limited log stream identifies dropped forwarded traffic by source, destination, and TCP ports. |

S01's SMB probe, S03, and S04 share the same destination and port. Run them in separate time windows so the router log entries can be matched to the individual cases. See the [segmented runbook](runbook.md#segmented-layout) for commands.
