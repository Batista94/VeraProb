# Test Plan — 20260717000001_fix_function_search_path

**Migration:** `supabase/migrations/20260717000001_fix_function_search_path.sql`
**Linter ID:** 0029 — `function_search_path_mutable`
**Risk:** Medium — behavioral change only if an attacker had already exploited schema squatting. No signature or ACL change.

---

## Problem

67 postgres-owned public functions lack a fixed `search_path`. PostgreSQL resolves unqualified object references at runtime using the session `search_path`. A caller with CREATE SCHEMA privilege can inject a schema early in the path, redirecting lookups (tables, types, functions) to attacker-controlled objects. For SECURITY DEFINER functions (6 in this batch) this executes with postgres-owner privileges.

---

## Fix

`ALTER FUNCTION public.<name>(...) SET search_path = 'public'` for non-SECURITY DEFINER functions.
`ALTER FUNCTION public.<name>(...) SET search_path = 'public, auth, extensions'` for SECURITY DEFINER functions.

Zero-downtime: `ALTER FUNCTION` acquires only `ShareUpdateExclusiveLock`. No body, ACL, or signature changes.

---

## Pre-migration Assertions

```sql
-- Must return 67 rows before migration
SELECT COUNT(*) AS cnt
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
  AND NOT EXISTS (
    SELECT 1 FROM pg_options_to_table(p.proconfig)
    WHERE option_name = 'search_path'
  );
-- Expected: cnt = 67
```

---

## Post-migration Assertions

```sql
-- 1. Zero functions missing search_path (postgres-owned, public schema)
SELECT COUNT(*) AS unfixed
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
  AND NOT EXISTS (
    SELECT 1 FROM pg_options_to_table(p.proconfig)
    WHERE option_name = 'search_path'
  );
-- Expected: unfixed = 0

-- 2. SECURITY DEFINER functions use wide search_path
SELECT proname, proconfig
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
  AND EXISTS (
    SELECT 1 FROM pg_options_to_table(p.proconfig)
    WHERE option_name = 'search_path'
  )
ORDER BY proname;
-- Expected: _edq_block_delete_after_update, auto_enqueue_sanction_recommended,
--           create_execution_for_operator, custom_access_token_hook,
--           get_current_asset_status, get_pending_sanctions_count
--           all have search_path containing 'public, auth, extensions'

-- 3. Trigger functions still fire on actual DML (smoke test)
-- This cannot be unit-tested in SQL alone; verify via make test-db after deploy.
```

---

## Rollback

```sql
-- Reset a specific function if breakage is detected:
ALTER FUNCTION public.<fn_name>(<args>) RESET search_path;
-- This restores the database-level default. Repeat per function as needed.
```

---

## Regression Risk

**Low.** The existing function bodies use qualified references (`public.`, `auth.`, `extensions.`). No function behavior changes unless an attack was already in progress.

**Exception to watch:** If any function body uses an unqualified reference to an `auth` or `extensions` object without schema prefix AND the function is non-SECURITY-DEFINER (which received only `search_path = 'public'`), a runtime error would surface. Monitor application logs for 60 minutes post-deploy.
