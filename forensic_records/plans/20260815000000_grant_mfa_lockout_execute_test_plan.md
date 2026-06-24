# Test Plan: grant_mfa_lockout_execute (Fix — MFA RPC 42501 regression)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260815000000_grant_mfa_lockout_execute.sql` | `20260815000000_grant_mfa_lockout_execute_test.sql` | ✅ |

## Objective

Restore EXECUTE on the three MFA circuit-breaker RPCs (`record_mfa_failure`,
`reset_mfa_lockout`, `check_mfa_lockout`) for the roles that legitimately call
them. `20260717000002` revoked EXECUTE `FROM PUBLIC, anon` to close an anon
SECURITY DEFINER bypass, but those functions' grants existed only via the PUBLIC
default. Since `service_role` is not a superuser and does not bypass function
ACLs, the revoke stripped EXECUTE from every non-owner role — breaking both the
`super-admin-proxy` edge function (`service_role`) and `SupabaseMfaRepository`
(`authenticated`). Symptom: `42501 permission denied for function
record_mfa_failure`.

## Root Cause

| Migration | Action | Effect |
|-----------|--------|--------|
| `20260418000001` | `CREATE FUNCTION` (no explicit grant) | EXECUTE granted to PUBLIC by default |
| `20260717000002` | `REVOKE EXECUTE … FROM PUBLIC, anon` | PUBLIC removed → service_role + authenticated also lose access (no explicit grant ever existed) |
| `20260815000000` | `GRANT EXECUTE … TO authenticated, service_role` | Legit callers restored; anon stays revoked |

## Strategy

Pure grant DDL inside `BEGIN/COMMIT` (idempotent, metadata-only → zero-downtime,
INV-DB). pgTAP asserts `has_function_privilege` for the two restored roles and
the continued absence for `anon`, per RPC.

## Test Scenarios (plan = 9)

| # | Role | RPC | Assertion | INV |
|---|------|-----|-----------|-----|
| T1 | authenticated | record_mfa_failure | has EXECUTE | INV-DATA-API-GRANT |
| T2 | authenticated | reset_mfa_lockout | has EXECUTE | INV-DATA-API-GRANT |
| T3 | authenticated | check_mfa_lockout | has EXECUTE | INV-DATA-API-GRANT |
| T4 | service_role | record_mfa_failure | has EXECUTE | INV-DATA-API-GRANT |
| T5 | service_role | reset_mfa_lockout | has EXECUTE | INV-DATA-API-GRANT |
| T6 | service_role | check_mfa_lockout | has EXECUTE | INV-DATA-API-GRANT |
| T7 | anon | record_mfa_failure | NO EXECUTE | INV-2 |
| T8 | anon | reset_mfa_lockout | NO EXECUTE | INV-2 |
| T9 | anon | check_mfa_lockout | NO EXECUTE | INV-2 |

## Notes

- Append-only: a new migration restores the grant; `20260717000002` is untouched.
- anon remaining revoked keeps the original anon-bypass fix intact — only the
  two authenticated server/app paths are restored.
- No table/type surface change → `supabase/types.database.ts` unaffected.
- Closes the failures in `test/integration/security/mfa_lockout_db_test.dart`
  (cases 23–28, 41–44) which call the RPCs via a `service_role` client.

## Council Sign-off

- Architect ✅ — No layer/contract change; pure ACL restoration
- Senior ✅ — Idempotent GRANT, signatures match `(uuid)` overload
- QA-Security ✅ — anon stays revoked (T7–T9 red-team); least-privilege preserved
- Business ✅ — Unblocks super-admin MFA login (prod-impacting outage fix)
- Lead Reviewer ✅ — 1:1 plan + pgTAP, regression-anchored

## Run Command

```bash
make test-db
```
