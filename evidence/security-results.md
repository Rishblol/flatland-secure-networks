# Person 5 security validation results

Tested revision `d75f7f5d16502831e35f6cf4d4c82b8d7d70c7b6` on Docker Engine 28.5.1 (Linux AMD64, Docker Desktop with WSL 2) and Compose v2.40.0-desktop.1.

All four fixed TCP connections succeeded in the flat layout. The same four connections timed out in the segmented layout, and each had a matching router SYN drop. B01–B08 passed in both layouts, and the service health checks passed before and after the probes.

- [Flat baseline log](security-flat.log)
- [Segmented validation log with router matches](security-segmented.log)
- [Validation design and coverage](../docs/security-validation.md)

| ID | Scope | Expected | Flat observed (UTC) | Segmented observed (UTC) |
|---|---|---|---|---|
| S01-app | Workstation → `app:8080` | Flat connects, segmented drops | **PASS** · Connected<br>`2026-11-21T05:40:11Z` | **PASS** · Timed out, router drop matched<br>`2026-11-21T05:40:24Z` |
| S01-database | Workstation → `database:5432` | Flat connects, segmented drops | **PASS** · Connected<br>`2026-11-21T05:40:12Z` | **PASS** · Timed out, router drop matched<br>`2026-11-21T05:40:27Z` |
| S01-file | Workstation → `file:445` | Flat connects, segmented drops | **PASS** · Connected<br>`2026-11-21T05:40:12Z` | **PASS** · Timed out, router drop matched<br>`2026-11-21T05:40:30Z` |
| S02 | Workstation → `database:22` (SSH transport) | Flat connects, segmented drops | **PASS** · Connected<br>`2026-11-21T05:40:13Z` | **PASS** · Timed out, router drop matched<br>`2026-11-21T05:40:34Z` |
| S03 | SMB transport and local share health | Flat connects, segmented drops, share is healthy | **PASS** · Uses S01-file and the file health check | **PASS** · Uses S01-file and the file health check |
| S04 fixture | Synthetic source and destination state | Source is available and the destination is absent before and after | **PASS** · Source available, destination absent twice | **PASS** · Source available, destination absent twice |
| S04 copy | End-to-end workstation SMB copy | Flat copy succeeds, segmented copy fails | **NOT RUN** | **NOT RUN** |
| L01 | Correlation for all fixed TCP probes | Router logs corroborate every segmented denial | **BASELINE** · Flat connectivity captured | **PASS** · Four of four probes matched |

S02 and S03 measure workstation TCP reachability. The authorized SSH session and local SMB share health serve as controls. Workstation SSH authentication, workstation SMB share interaction, and the end-to-end copy remain unverified.
