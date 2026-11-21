# Flat lab runbook

Run these commands from the repository root with Docker in Linux container mode and the Docker Compose plugin. The first build pulls base images and Debian packages. The running lab uses one internal Docker bridge with no published host ports. Run client commands with `docker compose exec` inside the appropriate source container.

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

## Segmented layout handoff

Use `lab/compose.services.yaml` as the first Compose input and the segmented topology as the second. The flat topology file is only for flat runs. Put the segmented layout under a separate project name so teammates can tell the two layouts apart. Attach each workload to its assigned zone and preserve the service names, ports, and fixtures above. For checks that need to work across isolated bridges, use the destination addresses from the segmented addressing plan or provide name resolution for those addresses.
