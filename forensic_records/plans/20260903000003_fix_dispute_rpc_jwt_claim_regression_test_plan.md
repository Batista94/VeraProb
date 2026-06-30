# Test Plan: 20260903000003 — Fix Dispute RPC JWT Claim Path Regression

**Migration:** `supabase/migrations/20260903000003_fix_dispute_rpc_jwt_claim_regression.sql`  
**Test file:** `supabase/tests/20260903000003_dispute_rpc_jwt_regression_test.sql`  
**Severity:** CRITICAL (BLOCK-1 — dispute workflow broken in production)  
**Invariants:** INV-2, INV-22, INV-26  
**Council:** QA/Security BLOCK-1 | Lead Reviewer final gate

---

## Regression Summary

Migration `20260901000006_fix_rpc_jwt_org_claim.sql` introduced a JWT claim path regression in all three dispute RPCs. It replaced the canonical `auth.jwt() -> 'app_metadata' ->> 'org_id'` with the legacy/stale top-level `auth.jwt() ->> 'organization_id'`.

The project JWT hook (`20260305171000`) injects org into `app_metadata.org_id` only. The top-level `organization_id` claim is unpopulated for all tenant sessions. Result: `v_jwt_org IS NULL` for every real user → 42501 on every dispute operation → entire dispute workflow broken.

This migration reverts all three RPCs to the canonical `app_metadata.org_id` path. No other logic is changed.

---

## Affected RPCs

| RPC | Params | Broken line in 20260901000006 |
|-----|--------|-------------------------------|
| `resolve_dispute` | 9 | line 41 |
| `reject_sanction` | 7 | line 211 |
| `approve_sanction` | 7 | line 328 |

---

## Test Cases

| TC | RPC | JWT | Expected |
|----|-----|-----|----------|
| TC1 | — | — | resolve_dispute has correct signature |
| TC2 | — | — | resolve_dispute is SECURITY DEFINER |
| TC3 | resolve_dispute | ONLY app_metadata.org_id (no top-level org_id) | LIVES_OK — regression smoke |
| TC4 | resolve_dispute | Same JWT, row already resolved | P0001 — idempotency |
| TC5 | reject_sanction | ONLY app_metadata.org_id | LIVES_OK — regression smoke |
| TC6 | approve_sanction | ONLY app_metadata.org_id | LIVES_OK — regression smoke |
| TC7 | resolve_dispute | app_metadata.org_id = Org B, p_org_id = Org A | 42501 — INV-22 anti-oracle |
| TC8 | reject_sanction | Cross-tenant | 42501 — INV-22 anti-oracle |
| TC9 | approve_sanction | Cross-tenant | 42501 — INV-22 anti-oracle |
| TC10 | resolve_dispute | app_metadata.org_id absent (NULL) | 42501 — INV-2 fail-closed |
| TC11 | reject_sanction | app_metadata.org_id absent | 42501 — INV-2 fail-closed |
| TC12 | approve_sanction | app_metadata.org_id absent | 42501 — INV-2 fail-closed |
| TC13 | resolve_dispute | — | service_role cannot EXECUTE |
| TC14 | reject_sanction | — | service_role cannot EXECUTE |
| TC15 | approve_sanction | — | service_role cannot EXECUTE |

**Critical distinction:** TC3/TC5/TC6 JWTs deliberately omit the top-level `organization_id` field. With the old (broken) code these would return 42501. With the fix they must succeed.

---

## Verification Steps

```bash
# 1. Reset DB and run all pgTAP tests
make test-db

# 2. Verify dispute workflow end-to-end (manual)
# Call resolve_dispute via Supabase Studio with a real tenant session token
# Confirm 200 OK with {"status": "..."} — not 42501

# 3. Full scanner pass
bash scripts/security/pr_full_scanner.sh

# 4. Flutter unit + widget tests
make test
```

---

## Advisory Findings (WARN-1, WARN-2, WARN-3)

These were identified during the feature/sparklines audit but do not block merge:

**WARN-1:** `get_financial_trend_sparkline` revokes `service_role`; `get_fleet_health_status` grants it. Policy drift — no security hole (both SECURITY DEFINER with explicit org check), but internal tooling calling either via service_role will get asymmetric results. Document or align in a follow-up migration.

**WARN-2:** `get_fleet_health_status` includes phantom devices (asset_id IS NULL) in the `fleet_active_ratio` denominator. Forensic accuracy issue — an org with many unbound device chips shows a misleadingly low active ratio on CFO dashboards. Document design intent or add `phantom_count` column.

**WARN-3:** Sparkline TC11 originally only asserted `IS NOT NULL` (does not crash). Strengthened to also assert `<= 90` elements (clamp enforcement). Applied inline in the existing test file.
