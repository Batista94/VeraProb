# Test Plan: `20260902000001_fleet_health_status_rpc` + `20260902000002_extend_alert_type_check`

## Migration Summary
- **`get_fleet_health_status`**: SECURITY DEFINER RPC returning classified hardware health (HEALTHY/DELAYED/OFFLINE/NEVER_SEEN) for all registered vehicles + phantom devices. Parameterized thresholds (`p_delayed_sec`, `p_offline_sec`). Per-device integrity score (WS-9 compatible) and 24h anomaly count.
- **`extend_alert_type_check`**: Extends `valid_alert_type` CHECK to include `TELEMETRY_SILENT` and `TELEGRAM_ORPHAN`.

## Test Coverage (14 assertions)

| ID | Category | Test | Invariant |
|----|----------|------|-----------|
| S1 | Structure | Function exists with signature `(uuid,int,int,int)` | — |
| S2 | Structure | Function is SECURITY DEFINER | INV-2 |
| HP1 | Classification | 30s gap → HEALTHY | — |
| HP2 | Classification | 20 min gap → DELAYED | — |
| HP3 | Classification | 2h gap → OFFLINE | — |
| HP4 | Classification | No telemetry → NEVER_SEEN | — |
| HP5 | Phantom Devices | `asset_id IS NULL` device included in results | — |
| HP6 | Anomaly Count | `KINEMATIC_ANOMALY` counted in `anomaly_count_24h` | INV-18 |
| HP7 | Exclusion | Retired vehicles not returned | — |
| HP8 | Sort Order | NEVER_SEEN sorted first (worst-first) | — |
| HP9 | Parameterized | Custom `p_delayed_sec=300` respects threshold | — |
| B1 | Tenant Isolation | Cross-org JWT → 0 rows | INV-22/26 |
| A1 | Alert Extension | `TELEMETRY_SILENT` accepted by CHECK | — |

## pgTAP File
`supabase/tests/20260902000001_fleet_health_status_rpc_test.sql`
