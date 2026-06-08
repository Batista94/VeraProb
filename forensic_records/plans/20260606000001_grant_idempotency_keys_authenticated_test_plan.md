# Test Plan: 20260606000001 — Grant authenticated access to idempotency_keys

## Migration
`supabase/migrations/20260606000001_grant_idempotency_keys_authenticated.sql`

## Purpose
Fixes CI Block #13 (INV-DATA-API-GRANT): migration `20260413000002` created `public.idempotency_keys` and three client RPC functions without any `GRANT` statements. PostgREST blocks all client requests with 403. This migration grants `SELECT, INSERT, UPDATE` on the table and `EXECUTE` on the three client-facing functions to the `authenticated` role.

## Scope

| Object | Type | Roles | Permissions |
|--------|------|-------|-------------|
| `public.idempotency_keys` | TABLE | `authenticated` | SELECT, INSERT, UPDATE |
| `public.idempotency_keys` | TABLE | `service_role` | ALL |
| `public.try_acquire_idempotency_key` | FUNCTION | `authenticated`, `service_role` | EXECUTE |
| `public.complete_idempotency_key` | FUNCTION | `authenticated`, `service_role` | EXECUTE |
| `public.fail_idempotency_key` | FUNCTION | `authenticated`, `service_role` | EXECUTE |
| `public.cleanup_expired_idempotency` | FUNCTION | `service_role` | EXECUTE |

## Verification SQL

```sql
-- 1. Table grants for authenticated
SELECT privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'authenticated'
  AND table_schema = 'public'
  AND table_name = 'idempotency_keys'
ORDER BY privilege_type;
-- Expected: INSERT, SELECT, UPDATE (DELETE must NOT appear)

-- 2. Function grants for authenticated
SELECT routine_name, privilege_type
FROM information_schema.routine_privileges
WHERE grantee = 'authenticated'
  AND routine_schema = 'public'
  AND routine_name IN (
    'try_acquire_idempotency_key',
    'complete_idempotency_key',
    'fail_idempotency_key'
  )
ORDER BY routine_name;
-- Expected: EXECUTE for all three functions

-- 3. DELETE must NOT be grantable to authenticated (trigger guard)
SELECT COUNT(*) FROM information_schema.role_table_grants
WHERE grantee = 'authenticated'
  AND table_name = 'idempotency_keys'
  AND privilege_type = 'DELETE';
-- Expected: 0
```

## Acceptance Criteria

1. `POST /rpc/try_acquire_idempotency_key` returns 200 (not 403) for an authenticated user.
2. `POST /rpc/complete_idempotency_key` and `POST /rpc/fail_idempotency_key` return 200.
3. `DELETE` on `idempotency_keys` for authenticated still blocked (trigger + missing grant).
4. `make test-db` passes with zero failures.
