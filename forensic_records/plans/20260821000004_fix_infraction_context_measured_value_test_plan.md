# Test Plan: fix_infraction_context_measured_value

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260821000004_fix_infraction_context_measured_value.sql` | `20260821000004_fix_infraction_context_measured_value_test.sql` | ✅ |

## Intent

`read_infraction_context` derived `measured_value` directly from `delta_value` (the
**excess** above threshold), not from `threshold + delta`. This produced:

- Portal: Medido = 9 km/h (delta), Limite = 80 km/h, Excesso = -71 km/h
- Correct: Medido = 89 km/h, Limite = 80 km/h, Excesso = +9 km/h

Root cause (`20260821000001`):
```sql
v_measured := ROUND(delta_value)::int;        -- ← delta IS excess, not measured
v_exceeded := v_measured - v_threshold;       -- ← 9 - 80 = -71
```

Fix (`20260821000004`, consolidated into `20260822000005`):
```sql
v_exceeded := ROUND(delta_value)::int;
v_measured := ROUND(threshold_value + delta_value)::int;
```

Note: `20260822000002_fix_location_label_regression.sql` ran after `000004` and
re-introduced the original bug. `20260822000005` is the authoritative definition
combining the location-label COALESCE fix and the correct math. This test file
validates the math contract regardless of which migration is the final definer.

## Test Scenarios

| # | Category | Scenario | Expected | INV |
|---|----------|----------|----------|-----|
| T1 | Projection | Integer delta=10, threshold=80 → `measured_value` | 90 | INV-4 |
| T2 | Projection | Integer delta=10, threshold=80 → `exceeded_by` | 10 | INV-4 |
| T3 | Bug Regression | Real case: delta=8.5, threshold=80 → `measured_value` | 89 (NOT 9) | INV-4 |
| T4 | Bug Regression | Real case: delta=8.5, threshold=80 → `exceeded_by` | 9 (NOT -71) | INV-4 |
| T5 | Null Guard | Missing delta → `measured_value` | NULL | INV-4 |
| T6 | Null Guard | Missing delta → `exceeded_by` | NULL | INV-4 |
| T7 | Rounding | delta=7.5, threshold=5.0 → `measured_value` | 13 (ROUND(12.5)) | INV-4 |
| T8 | Rounding | delta=7.5, threshold=5.0 → `exceeded_by` | 8 (ROUND(7.5)) | INV-4 |

## Council Sign-off

- **Senior:** `measured = ROUND(threshold + delta)` is the only semantically correct formula given VerdictEvidence serialisation ✅
- **QA/Security:** WHEN OTHERS → 42501 prevents internal cast errors from leaking; no access_count side-effect ✅
- **Lead Reviewer:** Superseded by `20260822000005` which is the live definer; this test plan documents the mathematical invariant ✅
