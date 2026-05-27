# Test Plan — 20260717000002_fix_anon_function_execute_revoke

**Migration:** `supabase/migrations/20260717000002_fix_anon_function_execute_revoke.sql`
**Linter ID:** 0027 — `anon_security_definer_function_executable`
**Risk:** HIGH — CRITICAL auth bypass closed. See vulnerability below.

---

## Vulnerability (CRITICAL)

Multiple `super_admin_*` functions guard authentication with:

```sql
IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
  IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
END IF;
```

When called as `anon`, `auth.jwt() ->> 'sub'` IS NULL → the entire check is **SKIPPED**. An unauthenticated HTTP POST to the PostgREST RPC endpoint is sufficient to invoke `super_admin_archive_organization`, `super_admin_create_organization`, etc. without credentials.

---

## Fix

`REVOKE EXECUTE ON FUNCTION public.<fn>(...) FROM PUBLIC, anon` for all SECURITY DEFINER functions except the 4 required for anonymous flows:
- `accept_contract_by_contractor(text)` — contractor URL token
- `get_contract_for_review(text)` — contractor review page
- `accept_invitation(text, uuid)` — invitation acceptance
- `custom_access_token_hook(jsonb)` — Supabase Auth JWT hook

---

## Pre-migration Vulnerability Proof

```sql
-- These functions should have anon EXECUTE BEFORE migration:
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND p.proname LIKE 'super_admin_%'
  AND (
    array_to_string(p.proacl, ',') LIKE '%=X/%'
    OR array_to_string(p.proacl, ',') LIKE '%anon=X/%'
  )
ORDER BY proname;
-- Expected pre-migration: 13 rows (all super_admin_* functions)
```

---

## Post-migration Assertions

```sql
-- 1. No SECURITY DEFINER functions callable by anon (except the 4 kept)
SELECT proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND (
    array_to_string(p.proacl, ',') LIKE '%=X/%'
    OR array_to_string(p.proacl, ',') LIKE '%anon=X/%'
  )
  AND p.proname NOT IN (
    'accept_contract_by_contractor',
    'get_contract_for_review',
    'accept_invitation',
    'custom_access_token_hook'
  )
ORDER BY proname;
-- Expected: 0 rows

-- 2. Kept functions still have anon EXECUTE
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'accept_contract_by_contractor',
    'get_contract_for_review',
    'accept_invitation',
    'custom_access_token_hook'
  )
  AND (
    array_to_string(p.proacl, ',') LIKE '%=X/%'
    OR array_to_string(p.proacl, ',') LIKE '%anon=X/%'
  )
ORDER BY proname;
-- Expected: 4 rows

-- 3. authenticated role still has EXECUTE on operational functions
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'super_admin_create_organization'
  AND array_to_string(p.proacl, ',') LIKE '%authenticated=X/%';
-- Expected: 1 row (authenticated still granted)
```

---

## Application Impact Verification

After deploy, run E2E suite to confirm:

```powershell
make test-e2e
```

Critical paths to exercise:
1. **Contractor accept flow** — uses `accept_contract_by_contractor` (anon, must still work)
2. **Invitation accept flow** — uses `accept_invitation` (anon, must still work)
3. **Super admin login + org create** — uses `super_admin_create_organization` (authenticated, must still work)
4. **Super admin archive org** — uses `super_admin_archive_organization` (authenticated, must still work)

---

## Rollback

```sql
-- Re-grant if an application path breaks unexpectedly:
GRANT EXECUTE ON FUNCTION public.<fn_name>(<args>) TO anon;
```

Prefer investigating root cause before rolling back — these revokes close a critical auth bypass.
