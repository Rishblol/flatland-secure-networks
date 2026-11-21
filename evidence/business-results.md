# Person 4 business validation

All eight approved business flows passed in both layouts at revision `71dce1fbb8c01dde57de1b0024aa89483b648f9f`.
The lab ran on Docker Engine 28.5.1 (Linux AMD64, Docker Desktop with WSL 2) and Compose v2.40.0-desktop.1.

Follow the [Flatland runbook](../docs/runbook.md) to reproduce the checks. The raw captures include service readiness, the commands, and the observed output for each flow.

- [Flat baseline log](business-flat.log)
- [Segmented validation log](business-segmented.log)

| ID | Path | Expected in both layouts | Flat observed (UTC) | Segmented observed (UTC) |
|---|---|---|---|---|
| B01 | Workstation → web, HTTPS 443 | HTTP 200, page contains `Flatland demo page` | **PASS** · HTTP 200, fixture page returned<br>`2026-11-21T05:12:02Z` | **PASS** · HTTP 200, fixture page returned<br>`2026-11-21T05:12:52Z` |
| B02 | Web → app, HTTP 8080 | HTTP 200, body is `healthy` | **PASS** · HTTP 200, `healthy`<br>`2026-11-21T05:12:02Z` | **PASS** · HTTP 200, `healthy`<br>`2026-11-21T05:12:53Z` |
| B03 | App → database, PostgreSQL 5432 | Read-only query returns `flatland-db-ok` | **PASS** · `flatland-db-ok`<br>`2026-11-21T05:12:03Z` | **PASS** · `flatland-db-ok`<br>`2026-11-21T05:12:53Z` |
| B04 | Jump → workstation, SSH 22 | `id -un` returns `lab` | **PASS** · `lab`<br>`2026-11-21T05:12:03Z` | **PASS** · `lab`<br>`2026-11-21T05:12:54Z` |
| B05 | Jump → web, SSH 22 | `id -un` returns `lab` | **PASS** · `lab`<br>`2026-11-21T05:12:04Z` | **PASS** · `lab`<br>`2026-11-21T05:12:55Z` |
| B06 | Jump → app, SSH 22 | `id -un` returns `lab` | **PASS** · `lab`<br>`2026-11-21T05:12:05Z` | **PASS** · `lab`<br>`2026-11-21T05:12:55Z` |
| B07 | Jump → database, SSH 22 | `id -un` returns `lab` | **PASS** · `lab`<br>`2026-11-21T05:12:05Z` | **PASS** · `lab`<br>`2026-11-21T05:12:56Z` |
| B08 | Jump → file, SSH 22 | `id -un` returns `lab` | **PASS** · `lab`<br>`2026-11-21T05:12:06Z` | **PASS** · `lab`<br>`2026-11-21T05:12:56Z` |

B03 followed the direct route within the shared Server zone. The segmented log also records a router allow-rule hit for each of the seven flows that crossed zones.
