# Test Plan: reason_code_curation_view (Item 5.5 — Curadoria de reason codes)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260814000004_reason_code_curation_view.sql` | `20260814000004_reason_code_curation_view_test.sql` | ✅ |

## Objective

Item 5.5 closes the closed-catalogue support debt: free-text written under any
`OTHER`-category code (`OTHER`, `LEGACY_UNCLASSIFIED`) is otherwise invisible to
analytics. The view `v_reason_code_curation_candidates` ranks that text by
frequency per org so the Product owner can promote recurring entries to global
codes. Process + owner are documented in the curation SOP
(`docs/governance/reason-code-curation-sop.md`); this migration delivers the
operable feed.

## Strategy

Structural + behavioral, as `postgres` inside `BEGIN/ROLLBACK`, with one
assertion executed under `SET ROLE authenticated` to prove the `security_invoker`
view inherits base-table RLS. Seeds two orgs (A, B) and five Org-A rows spanning
every filter branch (collapsible duplicates, legacy bucket, structured code,
blank text).

## Test Scenarios (plan = 7)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| T1 | Structure | View exists | `information_schema.views` | - |
| T2 | Security | `security_invoker = true` | `reloptions` contains flag | INV-2 / CI#11 |
| T3 | Grant | `authenticated` has SELECT | `has_table_privilege` | INV-DATA-API-GRANT |
| T4 | Behavior | Case/whitespace variants collapse to one group | `occurrence_count = 2` | B6 |
| T5 | Behavior | Only OTHER-category non-blank text surfaces | group count = 2 | B6 |
| T6 | Behavior | Structured (`SENSOR_FAULT`) text excluded | count = 0 | B6 |
| T7 | Isolation | Org-A session sees only Org-A candidates | count = 2 under `authenticated` | INV-1 / INV-22 |

## Notes

- `CREATE VIEW` is metadata-only DDL → zero-downtime (INV-DB). `DROP VIEW IF
  EXISTS` + `CREATE` (not `CREATE OR REPLACE`) guarantees the `security_invoker`
  option lands even over a prior definition (CI block #11 caveat).
- Filter is by catalogue **category** (`OTHER`), not a hard-coded code list, so
  the feed survives new OTHER-bucket codes and stays industry-agnostic (B6).
- Cross-org GLOBAL promotion pass runs under `service_role` (tenant sessions see
  only their own backlog via inherited RLS) — documented in the SOP.
- View DDL exposes a new public object to the Data API →
  `supabase/types.database.ts` regenerated and committed alongside.

## Council Sign-off

- Architect ✅ — Agnostic feed (category filter, no transport wording; B6)
- Senior ✅ — `security_invoker`, normalization (`lower(btrim())`), frequency rank
- QA-Security ✅ — Tenant isolation via inherited RLS; no anon grant; T7 red-team
- Business ✅ — Surfaces "why fines are inhibited" backlog; feeds catalogue growth
- Lead Reviewer ✅ — 1:1 plan + pgTAP, gates green

## Run Command

```bash
make test-db
```
