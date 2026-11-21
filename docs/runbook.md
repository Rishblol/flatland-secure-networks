# Flatland lab runbook

Run these commands from the repository root with Docker in Linux container mode and the Docker Compose plugin. The first build pulls base images and Debian packages. The flat lab uses one internal Docker bridge with no published host ports. Run client commands with `docker compose exec` inside the appropriate source container.

## Start and check readiness

```console
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml up --build --wait
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml ps
docker network inspect flatland-flat_flat
```

The five service hosts should report healthy and `jump` should be running. Compose assigns addresses and a gateway from Docker's address pools. Use the service names below for checks and inspect the bridge for the assigned subnet, gateway, and container addresses. If that subnet overlaps a connected VPN or another local network, stop the lab and set an unused subnet under `networks.flat.ipam.config` in the flat Compose file before restarting.

## Service contract

| Compose name | Listening ports | Fixture |
|---|---|---|
| `workstation` | TCP 22 | `/fixtures/transfer.txt` |
| `web` | TCP 443, TCP 22 | HTTPS `/` contains `Flatland demo page` |
| `app` | TCP 8080, TCP 22 | HTTP `/health` returns `healthy` |
| `database` | TCP 5432, TCP 22 | Database `flatland`, table `lab_fixture`, ID `1` returns `flatland-db-ok` |
| `file` | TCP 445, TCP 22 | Authenticated SMB share `transfer` at `/srv/transfer`. Starts empty. |
| `jump` | None | SSH client and `sshpass` |

- SSH uses `lab` / `flatland-ssh-demo` on all five destinations. The authorized command `id -un` returns `lab`. The workstation and jump host have `sshpass` for repeatable checks.
- PostgreSQL fixture queries use `lab_reader` / `flatland-reader-demo`.
- SMB uses `lab` / `flatland-smb-demo`.
- The web container generates a self-signed certificate for `web` on first start. The example uses `curl -k` for the isolated demo. The certificate is at `/etc/nginx/lab-tls/web.crt` in `web` if a caller needs certificate verification.

## Run business validation

Once the flat services are healthy, run the following from Bash. Start the [segmented layout](#segmented-layout) and wait for its services and router before running the second command.

```sh
bash scripts/check-business.sh flat
bash scripts/check-business.sh segmented
```

The runner uses the named Compose project for each layout and checks B01–B08 from the source containers in the [flow matrix](flow-matrix.md#business-flows). B01 accepts the lab's self-signed HTTPS certificate. The SSH checks use the disposable `lab` account and accept newly generated host keys for each run without persisting them. The database check reads the fixture with `lab_reader`.

Capture each command's output in a separate log file for the acceptance handoff. Each check includes its UTC timestamp, path, expected result, and observed command output. The runner exits `0` when all eight pass, `1` when any flow fails, and `2` for invalid usage or an unavailable lab. It reports the remaining checks after a flow fails.

## Check the service fixtures

```console
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml exec -T workstation curl -fkSs https://web/
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml exec -T web curl -fsS http://app:8080/health
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml exec -T -e PGPASSWORD=flatland-reader-demo app psql -X -h database -U lab_reader -d flatland -Atc "SELECT value FROM lab_fixture WHERE id = 1"
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml exec -T -e SSHPASS=flatland-ssh-demo jump sshpass -e ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new workstation id -un
```

Use the same jump-host command with `web`, `app`, `database`, and `file` to check the remaining SSH destinations. Recreating a destination generates new SSH host keys. Run checks from a fresh jump container after a full reset.

For the security validation handoff, S01 can use the internal endpoints `app:8080`, `database:5432`, and `file:445`. For S04, the source fixture is `workstation:/fixtures/transfer.txt` and the destination is `file:/srv/transfer/transfer.txt` via SMB on TCP 445. S03 can check access to the share without writing a file. Reset just the S04 destination between consecutive runs with the following command.

```console
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml exec -T file rm -f /srv/transfer/transfer.txt
```

## Reset or tear down

The command removes the flat lab containers and their generated fixtures, including the PostgreSQL volume. Run the startup command again for a clean baseline.

```console
docker compose -f lab/compose.services.yaml -f lab/compose.flat.yaml down --volumes
```

## Segmented layout

Use a rootful Docker Engine 28.0 or newer on Linux and Docker Compose 2.36 or newer. The Docker host kernel needs dummy and macvlan links, nftables with connection tracking, and NFLOG. The segmented project is named `flatland-segmented`. Its four macvlan networks are internal and use Docker-created dummy parent links. See the [diagram](diagram.md) and [flow matrix](flow-matrix.md). [Docker macvlan requirements](https://docs.docker.com/engine/network/drivers/macvlan/) · [Compose interface naming](https://docs.docker.com/reference/compose-file/services/#interface_name)

### Check subnets and start

Run these on the Docker host with any usual VPN connected. Compare the connected routes and Docker pools with `10.149.240.0/24`. If there is an overlap, choose a free `/24` and update the addressing in the segmented Compose file, firewall rules, diagram, and matrix together.

```console
ip -4 route show table all
docker network ls -q | xargs -r docker network inspect --format '{{.Name}} {{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

In a shell at the repository root, define this shortcut and start the segmented lab.

```sh
segmented() {
    docker compose -f lab/compose.services.yaml -f lab/compose.segmented.yaml "$@"
}

segmented config --quiet
segmented up --build --wait
segmented ps
```

Compose enables IPv4 forwarding in the router namespace and creates its macvlan interfaces in private mode. The interfaces stay isolated until the startup script loads nftables and switches them to bridge mode. Compose waits for the NFLOG listener before starting workloads. Workload entrypoints install their static route, switch their own interface to bridge mode, and drop `NET_ADMIN` from the service process tree. Use `segmented exec -T --user lab workstation ...` for checks in the workstation user role.

### Verify routing and policy

```sh
segmented exec -T router ip -br -4 addr
segmented exec -T router ip -4 route
segmented exec -T workstation ip -4 route get 10.149.240.74
segmented exec -T web ip -4 route get 10.149.240.10
segmented exec -T app ip -4 route get 10.149.240.139
segmented exec -T router nft list table inet flatland
```

Check that the router has the four expected `zone-*` interfaces. The workstation and web routes should show their own zone's router as the next hop. The app-to-database route should go directly over `eth0`. Use `segmented config` to confirm each workload has one network attachment and no service publishes host ports.

Use the existing fixture checks with the segmented command prefix. Static name mappings keep the same destinations usable in both layouts.

```sh
segmented exec -T --user lab workstation curl -fkSs --max-time 5 https://web/
segmented exec -T web curl -fsS --max-time 5 http://app:8080/health
segmented exec -T -e PGPASSWORD=flatland-reader-demo app psql -X -h database -U lab_reader -d flatland -Atc "SELECT value FROM lab_fixture WHERE id = 1"
```

### Read firewall logs and reload the policy

```sh
segmented logs --timestamps --since 5m router
segmented exec -T router nft list chain inet flatland deny_forward
segmented exec -T router nft --check --file /etc/flatland/firewall/flatland.nft
segmented exec -T router nft --file /etc/flatland/firewall/flatland.nft
```

Each `flatland-forward-drop` line records a dropped forwarded packet. Match `SRC`, `DST`, `SPT`, `DPT`, and the timestamp to the test case. The `IN` and `OUT` fields identify the source and destination zone interfaces. Logging is limited to 10 packets per second with an initial burst of 20. The drop counter still counts packets above the logging limit. A reload replaces the Flatland table atomically, resets its counters, and keeps connection-tracking state for existing connections. Recreate the router when testing a policy change that must also terminate established sessions.

If the router does not become healthy, use `segmented logs router` to check policy loading, the IPv4 forwarding setting, and the NFLOG listener. If nftables reports syntax errors with `\r` in an older Windows checkout, use a fresh checkout to apply the repository's LF setting for `firewall/flatland.nft`. If a workload does not become healthy, check `segmented logs <service>` and `segmented ps`. Save logs before teardown.

### Reset fixtures and tear down

```sh
segmented exec -T file rm -f /srv/transfer/transfer.txt
segmented down --volumes
```

The first command clears the S04 destination fixture between runs. The second removes the segmented project and its database volume.
