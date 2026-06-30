# Test Plan: `20260902000002_extend_alert_type_check`

## Migration Summary

Widens the `valid_alert_type` CHECK constraint to include `TELEMETRY_SILENT` (Phase 10.6)
while carrying all 8 previously established types. Also widens
`chk_alert_driver_attribution` to exempt `TELEMETRY_SILENT` from the driver_id
requirement, maintaining its intentionally NOT VALID state.

## Test Coverage (9 assertions)

| ID | Category | Test | Invariant |
|----|----------|------|-----------|
| C1 | New Type | `TELEMETRY_SILENT` accepted by `valid_alert_type` CHECK | — |
| C2 | Regression | `DISPUTE_DEFENSE_SUBMITTED` still accepted (was dropped in original draft) | — |
| C3 | Regression | `SLA_BREACH` still accepted | — |
| C4 | Regression | `POTENTIAL_TIME_FRAUD` still accepted | — |
| C5 | Rejection | Unknown type `PHANTOM_TYPE` rejected (23514) | INV-10 |
| D1 | Constraint State | `chk_alert_driver_attribution` remains NOT VALID | INV-DB |
| D2 | New Exemption | `TELEMETRY_SILENT` without `driver_id` accepted | — |
| D3 | Regression | `DISPUTE_DEFENSE_SUBMITTED` still exempt from `driver_id` | — |
| D4 | Guard | `DEVIATION` without `driver_id` still blocked (23514) | INV-10 |

## Design Notes

- `chk_alert_driver_attribution` is intentionally NOT VALID (older rows predate driver
  attribution; a VALIDATE scan would fail on them). This state was established in
  20260818000004 and is preserved across 20260827 and this migration.
- D2 is the primary new behaviour added by this migration's attribution guard change.
- C2–C4 are regression guards: the initial version of this migration silently dropped 4
  established types when rebuilding the CHECK from scratch.

## pgTAP File

`supabase/tests/20260902000002_extend_alert_type_check_test.sql`
