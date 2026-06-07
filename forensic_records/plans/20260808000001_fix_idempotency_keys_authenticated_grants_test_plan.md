# Test Plan: 20260808000001 — Fix idempotency_keys authenticated grants

## Migration
`supabase/migrations/20260808000001_fix_idempotency_keys_authenticated_grants.sql`

## Purpose
UAT CT04 regression: migration `20260717000005` incorrectly revoked all permissions from the `authenticated` role on the `idempotency_keys` table. Since `try_acquire_idempotency_key` is a SECURITY INVOKER function, client queries using it were blocked with a 42501 permission error, preventing `plan_declarations` inserts.
This migration restores `SELECT`, `INSERT`, and `UPDATE` grants on `public.idempotency_keys` to the `authenticated` role (originally applied in `20260606000001`).

## Scope

| Object | Type | Roles | Permissions |
|--------|------|-------|-------------|
| `public.idempotency_keys` | TABLE | `authenticated` | SELECT, INSERT, UPDATE |

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
```

## Acceptance Criteria

1. The `authenticated` role is granted `SELECT`, `INSERT`, and `UPDATE` privileges on `public.idempotency_keys`.
2. `make test-db` passes with zero failures.
