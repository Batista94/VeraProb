# Test Plan: fix_measured_value_post_location_regression

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260822000005_fix_measured_value_post_location_regression.sql` | `20260822000005_fix_measured_value_post_location_regression_test.sql` | ✅ |

## Intent

`20260822000002_fix_location_label_regression.sql` ran **after** the math fix
(`20260821000004`) and re-introduced the original bug by overwriting
`read_infraction_context` with the buggy formula:

```sql
-- re-introduced by 20260822000002:
v_measured := ROUND(delta_value)::int;        -- ← WRONG: delta is excess
v_exceeded := v_measured - v_threshold;       -- ← WRONG: produces negative values
```

`20260822000005` is the **authoritative** definition of `read_infraction_context`.
It combines:
1. **Correct math** from `20260821000004`: `exceeded = ROUND(delta)`, `measured = ROUND(threshold + delta)`
2. **Location COALESCE priority** from `20260822000002`: `geofence_name → address → location_label → lat,lng`

This test validates both independently: the math regression (measured/exceeded) cannot
be broken by a future location-label change, and the COALESCE priority is fully covered.

## Test Scenarios

| # | Category | Scenario | Expected | INV |
|---|----------|----------|----------|-----|
| T1 | Location | `geofence_name` + `address` + lat/lng present → location_label | `geofence_name` wins | — |
| T2 | Location | No `geofence_name`, `address` + lat/lng present → location_label | `address` wins | — |
| T3 | Location | Only `location_label` field → location_label | `location_label` field | — |
| T4 | Location | Only lat + lng → location_label | `"lat,lng"` concatenation | — |
| T5 | Location | No location fields at all → location_label | `'-'` | — |
| T6 | Math regression | Computed with real values after location fix → `measured_value` | `threshold + delta` | INV-4 |
| T7 | Math regression | Same row → `exceeded_by` | `ROUND(delta)`, not `measured - threshold` | INV-4 |

## Council Sign-off

- **Senior:** COALESCE priority matches `20260820000003` intent; `000005` resolves the merge conflict between location fix and math fix ✅
- **QA/Security:** WHEN OTHERS guard intact; no new disclosure surface introduced ✅
- **Lead Reviewer:** `pr_scanner: ignore-regression` comment justified — this migration supersedes two prior conflicting patches ✅
