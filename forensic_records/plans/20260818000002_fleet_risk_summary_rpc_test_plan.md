# Test Plan: get_fleet_risk_summary (Sprint C — Read Models)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260818000002_fleet_risk_summary_rpc.sql` | `20260818000002_fleet_risk_summary_rpc_test.sql` | ✅ |

## Intent

Server-side SLA breach-risk ranking for the fleet Risk Thermometer, replacing a
Dart loop that pulled every active window into memory. Computes `risk_bps` in SQL
**byte-identical** to `SlaBreachRiskCalculator` (INV-15) over `execution_states`
filtered to `('planned','inTransit')`. SECURITY DEFINER with an anti-oracle JWT
org gate (0 rows on mismatch, INV-26).

## Risk Math (mirrors the Dart calculator)

```
buffer_secs = (total_secs * 1500 + 5000) / 10000   -- 15% buffer, round½-away-0
risk_bps    = buffer>0 ? (elapsed * 10000) / buffer : (elapsed>=0 ? 10000 : -10000)
```

## Test Scenarios (8 assertions)

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| S1 | Structure | RPC `get_fleet_risk_summary(uuid,int)` exists | - |
| S2 | Structure | RPC is SECURITY DEFINER | INV-2 |
| HP1 | Determinism | mid-buffer window: risk_bps matches calculator formula exactly | INV-5/15 |
| HP2 | Boundary | window fully before buffer (early) → risk_bps < 0 (safe) | INV-15 |
| HP3 | Boundary | window past deadline → risk_bps > 10000 (breached) | INV-15 |
| HP4 | Filtering | `completed`/`inhibited` windows excluded; only active ranked | - |
| HP5 | Ordering | worst (highest risk_bps) returned first; p_limit honored | - |
| B1 | Tenant | cross-org caller → 0 rows (no error) | INV-22/26 |

## Council Sign-off

- Architect ✅ — Read path over execution_states projection; no new state.
- Senior ✅ — Integer math mirrors domain calculator; reuses partial index.
- QA-Security ✅ — JWT org gate, anti-oracle 0 rows; degenerate windows excluded.
- Business ✅ — Powers the at-a-glance fleet Risk Thermometer.
- Lead Reviewer ✅ — Council-approved plan (Sprint C, this migration).

## Run Command

```bash
make test-db
```
