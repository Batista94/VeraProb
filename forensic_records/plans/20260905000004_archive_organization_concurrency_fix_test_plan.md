# 20260905000004_archive_organization_concurrency_fix Test Plan

## Objective
Make `super_admin_archive_organization` idempotent under concurrent invocation
(double-click / retry / multi-tab), so that K racing calls archive the org
exactly once and append exactly one `ORG_ARCHIVED` audit record.

## Defect
The prior body (`20260707000000`) used check-then-act: two `EXISTS` reads for
404-parity and already-archived, followed by an unguarded `UPDATE`. Two
concurrent transactions both pass the `status = 'ARCHIVED'` check before either
commits (TOCTOU), so both run the full cascade and both `INSERT` an audit row.

## Fix
Lock-then-check: `SELECT status ... WHERE id = p_org_id FOR UPDATE`. Concurrent
callers serialise on the organization row lock; the loser blocks, re-reads
`status = 'ARCHIVED'` after the winner commits, and raises P0003. Cascade A–F,
error codes, INV-26 404-parity, and the JWT guard are preserved verbatim.

## Invariants Covered
- **INV-3 (Append-Only Audit):** exactly one `ORG_ARCHIVED` row per archival, never duplicated by a race.
- **INV-10 (Typed Errors):** already-archived → P0003, now honoured for the concurrent loser (previously it silently succeeded and duplicated).
- **INV-26 (404-Parity):** not-found AND soft-deleted → P0002 (unchanged).

## Test Coverage
1. **Concurrency (the fix target)** — `test/integration/e2e/superadmin/property_double_click_idempotency_test.dart`
   (Property 6). 100 iterations: K∈{2..5} concurrent `super_admin_archive_organization`
   calls via `Future.wait` against `service_role`. Asserts org status = ARCHIVED
   and `count(system_audit_log WHERE event_type='ORG_ARCHIVED') = 1`. True
   parallelism requires two client connections (dblink self-connect is blocked in
   local Supabase — see concurrency-test-harness note), so this lives in Dart E2E,
   not pgTAP.
2. **Guard regression (sequential)** — `supabase/tests/archive_org_preservation_test.sql`
   (plan 10). Verifies the fix leaves the JWT guard (42501), 404-parity (P0002),
   and idempotency (P0003) error codes unchanged.
3. **Happy-path audit completeness** — `test/integration/e2e/superadmin/property_audit_trail_test.dart`
   (Property 4). Single archive → exactly one `ORG_ARCHIVED` audit record with
   full payload.

## Expected Result
- Before fix: `property_double_click_idempotency` fails ~98/100 (`Encontrados: 2`).
- After fix: `property_double_click_idempotency` passes 100/100; preservation and
  audit-trail suites remain green.
