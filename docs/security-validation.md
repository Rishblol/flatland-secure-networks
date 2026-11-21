# Person 5 security validation design

The workstation validation measures the effect of default-deny on the documented User-to-Server paths. The same four TCP connection checks run in the flat and segmented projects. A segmented denial requires a healthy destination, a timed-out connection, and a matching router log. The lab uses synthetic data and disposable credentials. These results describe the isolated Docker lab.

| Phase | What runs | Decision and design principle |
|---|---|---|
| Scope and readiness | Check container health and resolve the workstation and destinations from their expected Compose networks. Check availability of the synthetic source fixture and inspect the destination path. | Fixed projects, roles, and ports keep traffic within the lab. An unready service or missing prerequisite makes the run inconclusive. |
| Authorized controls | Run the existing B01–B08 suite in the same layout. | Reuse the business fixtures to distinguish a functioning service from a policy denial. B01 confirms approved HTTPS, B07 confirms authorized database SSH, and the file service health check confirms local SMB share access. |
| Flat baseline | Open one bounded TCP connection to each fixed endpoint from the unprivileged workstation role. | Require each connection to succeed before using that endpoint in a before-and-after comparison. Reuse the same SMB observation for S01 and S03 because their transport endpoints are identical. |
| Segmented comparison | Make the same connections from the workstation. Correlate each timeout with router NFLOG using the probe start time, both IPs and ports, the TCP SYN flag, and the ingress and egress interfaces. | Require positive drop evidence. The per-probe source ports distinguish checks on repeated runs, and each probe uses a two-second connection budget. Keep matching log lines with the observation. |
| Final checks and handoff | Confirm service health again, check the destination fixture state, then report the result and retain the log with the tested revision. | An unavailable service at the final check invalidates the run. The fixture checks are read-only, so reruns preserve lab state. Capture the flat output before the segmented output. |

S01 covers `app:8080`, `database:5432`, and `file:445`. S02 and S03 cover the workstation TCP paths to `database:22` and `file:445`. The business suite and Docker health checks supply the authorized SSH and SMB controls. S04 records source fixture availability and destination fixture absence, with the segmented SMB transport result referenced from S03. The end-to-end workstation SMB copy is recorded as `NOT_RUN`. The workstation SSH session and SMB share interaction also remain unverified at the application layer.

L01 passes only when all four segmented observations have matching router logs. Its flat status is `BASELINE`. A run exits `0` when its transport, business, and fixture controls pass, `1` when a transport or fixture result fails, and `2` for invalid usage or an inconclusive run, including unavailable router logs. Review both layout logs before claiming segmentation changed a path.

Use the commands in the [Flatland runbook](runbook.md#run-security-validation). The original acceptance checks are listed in the [project README](../README.md#acceptance-checks).

Run `bash tests/check-security.sh` for the Docker-free regression checks. The cases cover healthy layouts, an unexpected connection, unrelated or unavailable router logs, an unhealthy destination, and missing or preexisting fixture state.
