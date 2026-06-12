# Test Plan — 20260815000001_restore_execute_grants_revoke_regression

**Migration:** `supabase/migrations/20260815000001_restore_execute_grants_revoke_regression.sql`
**Type:** RBAC grant remediation (no schema/DDL change). Append-only.
**Invariants:** INV-1, INV-2, INV-22, INV-DATA-API-GRANT.

## Context

`20260717000002` revoked EXECUTE `FROM PUBLIC, anon` on a large SECURITY DEFINER set.
For functions whose EXECUTE was held only via the PUBLIC default (no explicit
`service_role`/`authenticated` grant — or that were later recreated, resetting
their ACL) this collaterally stripped trusted roles. On a fresh `supabase db
reset` the CI gates failed:

- Coverage Gate → `accept_invitation` (service_role) 42501.
- SuperAdmin E2E Gate → `super_admin_create_organization` (service_role bootstrap)
  + `super_admin_archive_organization` (authenticated UI path, also missing
  service_role) → 52-test cascade.

The fix restores EXECUTE to the legitimate roles, keeping `anon` revoked.

## Assertions (pgTAP — `supabase/tests/20260815000001_*_test.sql`)

| # | Assertion | Rationale |
|---|-----------|-----------|
| G1 | `authenticated` has EXECUTE on `super_admin_create_organization` | app path |
| G2 | `service_role` has EXECUTE on `super_admin_create_organization` | E2E bootstrap |
| G3 | `authenticated` has EXECUTE on `super_admin_archive_organization` | UI path (was owner-only) |
| G4 | `service_role` has EXECUTE on `super_admin_archive_organization` | harness |
| G5 | `service_role` has EXECUTE on `accept_invitation` | coverage-gate race harness |
| G6 | `service_role` has EXECUTE on every super_admin_* in scope | E2E family recovery |
| G7 | `service_role` has EXECUTE on `test_cleanup_forensic_data` | CI fixture |
| A1 | `anon` does NOT have EXECUTE on `super_admin_create_organization` | INV-2 preserved |
| A2 | `anon` does NOT have EXECUTE on `super_admin_archive_organization` | INV-2 preserved |
| A3 | `authenticated` does NOT have EXECUTE on `test_cleanup_forensic_data` | prod safety (service_role-only) |
| R1 | `service_role` still does NOT have EXECUTE on `resolve_dispute` | Phase 10.6 lock intact |
| R2 | `service_role` still does NOT have EXECUTE on `attach_dispute_evidence` | Phase 10.6 lock intact |

## Manual / CI verification

- `supabase db reset` then re-query ACLs (no owner-only / missing-trusted-role rows).
- `flutter test test/integration/rls_isolation_test.dart` Case 12 → exactly one winner.
- SuperAdmin E2E Gate green (`make test-e2e`).
