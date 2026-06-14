# Test Plan: mv_carrier_performance + get_carrier_performance_ranking (Sprint C)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260818000001_carrier_performance_mv.sql` | `20260818000001_carrier_performance_mv_test.sql` | ✅ |

## Intent

Per-(organization, contract) carrier compliance scorecard. Obligation counts
aggregate `shadow_verdicts`; `dispute_count` + `total_fine_exposure_cents` come
from `sanction_review_queue`. The MV has no RLS, so it is locked to
`service_role`; tenant access is ONLY via the SECURITY DEFINER RPC
`get_carrier_performance_ranking`, which gates on the JWT `app_metadata.org_id`
and returns **0 rows** on mismatch (anti-oracle INV-26). Worst performers first
(`compliance_rate_bps ASC`). Rates are integer basis points (INV-5).

## Test Scenarios (10 assertions)

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| S1 | Structure | MV `mv_carrier_performance` exists | - |
| S2 | Structure | unique index `uq_mv_carrier_performance (org, contract)` present (REFRESH CONCURRENTLY) | INV-DB |
| S3 | Structure | RPC `get_carrier_performance_ranking(uuid,int)` exists | - |
| S4 | Structure | RPC is SECURITY DEFINER | INV-2 |
| HP1 | Arithmetic | `compliance_rate_bps` 8 executed / 10 obligations = 8000 exact | INV-5 |
| HP2 | Arithmetic | `total_fine_exposure_cents` = COALESCE SUM of disputed fine_cents | INV-4 |
| HP3 | Arithmetic | `dispute_rate_bps` = disputes / total obligations (bps) | INV-5 |
| B1 | Confidentiality | direct SELECT on MV by `authenticated` → permission denied | INV-22 |
| B2 | Tenant | RPC cross-org caller → 0 rows (no error) | INV-22/26 |
| HP4 | Ordering | RPC returns own-org rows, worst compliance first | - |

## Council Sign-off

- Architect ✅ — MV over append-only sources; service_role-only; RPC projection.
- Senior ✅ — Integer bps, GREATEST denominator guard, REFRESH CONCURRENTLY index.
- QA-Security ✅ — No MV grant to tenants; RPC JWT org gate, anti-oracle 0 rows.
- Business ✅ — Carrier ranking is the CFO/dispatcher demo hook.
- Lead Reviewer ✅ — Council-approved plan (Sprint C, this migration).

## Run Command

```bash
make test-db
```
