# Test Plan: 20260901000005 — get_financial_trend_sparkline

## Migration
`supabase/migrations/20260901000005_get_financial_trend_sparkline.sql`

## Scope
RPC `public.get_financial_trend_sparkline(p_org_id UUID, p_days INTEGER DEFAULT 7)`
returns JSONB array of daily sparkline points for CFO KPI cards.

## Invariants
INV-2 (org claim), INV-26 (anti-oracle 42501), INV-6 (UTC TIMESTAMPTZ),
INV-DB (non-blocking index), INV-DATA-API-GRANT (function grants).

## Test Cases

| TC | Description | Expected |
|----|-------------|----------|
| TC1 | `has_function` check | passes |
| TC2 | `prosecdef = true` (SECURITY DEFINER) | passes |
| TC3 | `authenticated` has EXECUTE grant | passes |
| TC4 | Org-A data: correct protected/at_risk/lost cents, ordered by date | exact JSONB array match |
| TC5 | p_days window filter: snapshot outside window excluded | empty or filtered array |
| TC6 | `contract_id IS NULL` filter: contract-level row excluded | not in result |
| TC7 | Superseded dedup: earlier snapshot in chain excluded, only canonical kept | single point per day |
| TC8 | Cross-tenant IDOR: Org-A claim + p_org_id = Org-B → `42501` anti-oracle | `throws_ok` |
| TC9 | Missing org_id claim → `42501` | `throws_ok` |
| TC10 | p_org_id NULL → `42501` | `throws_ok` |
| TC11 | `p_days` clamp: p_days=200 → treated as 90 (no crash, bounded window) | passes |

## pgTAP File
`supabase/tests/20260901000005_get_financial_trend_sparkline_test.sql`

## Verification Steps
1. `make test-db` — all 11 TCs pass.
2. `scripts/sync_db_types.sh` + `git status` — `types.database.ts` regenerated with new fn.
3. `make test` — Dart unit + widget suite green.
4. `make run` — Dashboard KPI cards show sparklines; 7d/30d toggle instant (cached).
5. `bash scripts/security/pr_full_scanner.sh` — must pass before PR.
