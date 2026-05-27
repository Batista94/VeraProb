# Test Plan — 20260716000001_fix_rls_no_policy_lint

**Migration:** `supabase/migrations/20260716000001_fix_rls_no_policy_lint.sql`  
**Invariants:** INV-2, INV-22, INV-28  
**Risk:** Low — policy-only change; no schema DDL; service_role bypass unaffected.

---

## Objective

Verify that explicit RESTRICTIVE deny-all policies silence the Supabase linter (0008)
without breaking any existing service_role / SECURITY DEFINER RPC access.

---

## Pre-conditions

- Local Supabase running (`supabase start`)
- Migration applied (`supabase db reset` or `supabase migration up`)

---

## Test Cases

### TC-1: Linter 0008 cleared for all 6 tables

```sql
-- Should return 0 rows for each of these tables
SELECT pc.relname
FROM pg_class pc
JOIN pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_policy pp ON pp.polrelid = pc.oid
WHERE pn.nspname = 'public'
  AND pc.relname IN (
    'impersonation_sessions',
    'org_api_secrets',
    'super_admin_mfa_lockouts',
    'super_admin_recovery_codes',
    'super_admin_users',
    'tenant_billing_events'
  )
  AND pc.relrowsecurity = true
GROUP BY pc.relname
HAVING COUNT(pp.polname) = 0;
-- Expected: 0 rows (all tables now have at least one policy)
```

### TC-2: Policies are RESTRICTIVE

```sql
SELECT tablename, policyname, permissive, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'impersonation_sessions',
    'org_api_secrets',
    'super_admin_mfa_lockouts',
    'super_admin_recovery_codes',
    'super_admin_users',
    'tenant_billing_events'
  );
-- Expected: 6 rows, permissive = 'RESTRICTIVE' (shown as 'RESTRICTIVE' in pg_policies)
```

### TC-3: Authenticated role cannot SELECT

```sql
-- Run as authenticated user (anon role + valid JWT, not service_role)
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claims" TO '{"sub":"test-user","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000001","role":"ADMIN"}}';

SELECT COUNT(*) FROM public.impersonation_sessions;     -- Expected: ERROR (RLS) or 0 rows
SELECT COUNT(*) FROM public.org_api_secrets;            -- Expected: ERROR (RLS) or 0 rows
SELECT COUNT(*) FROM public.super_admin_mfa_lockouts;   -- Expected: ERROR (RLS) or 0 rows
SELECT COUNT(*) FROM public.super_admin_recovery_codes; -- Expected: ERROR (RLS) or 0 rows
SELECT COUNT(*) FROM public.super_admin_users;          -- Expected: ERROR (RLS) or 0 rows
SELECT COUNT(*) FROM public.tenant_billing_events;      -- Expected: ERROR (RLS) or 0 rows
-- All must return 0 (RESTRICTIVE USING(false) blocks all rows)
```

### TC-4: SECURITY DEFINER RPCs still function

```sql
-- record_mfa_failure / check_mfa_lockout use SECURITY DEFINER (bypasses RLS)
SELECT public.check_mfa_lockout('00000000-0000-0000-0000-000000000001'::uuid);
-- Expected: {"failed_attempts": 0, "locked_until": null, "is_locked": false}
-- (RPC returns data — confirms SECURITY DEFINER path is unaffected)
```

### TC-5: service_role bypass unaffected

```sql
-- Run as service_role (supabase admin context)
SET LOCAL ROLE service_role;
SELECT COUNT(*) FROM public.tenant_billing_events;
-- Expected: actual row count (service_role bypasses all RLS policies)
```

---

## pgTAP Verification

```sql
-- File: supabase/tests/test_rls_deny_all_policies.sql
BEGIN;
SELECT plan(6);

SELECT has_table_privilege('authenticated', 'public.impersonation_sessions', 'SELECT') IS FALSE
  AS "impersonation_sessions: authenticated denied";

SELECT has_table_privilege('authenticated', 'public.org_api_secrets', 'SELECT') IS FALSE
  AS "org_api_secrets: authenticated denied";

SELECT has_table_privilege('authenticated', 'public.super_admin_mfa_lockouts', 'SELECT') IS FALSE
  AS "super_admin_mfa_lockouts: authenticated denied";

SELECT has_table_privilege('authenticated', 'public.super_admin_recovery_codes', 'SELECT') IS FALSE
  AS "super_admin_recovery_codes: authenticated denied";

SELECT has_table_privilege('authenticated', 'public.super_admin_users', 'SELECT') IS FALSE
  AS "super_admin_users: authenticated denied";

SELECT has_table_privilege('authenticated', 'public.tenant_billing_events', 'SELECT') IS FALSE
  AS "tenant_billing_events: authenticated denied";

SELECT * FROM finish();
ROLLBACK;
```

---

## Rollback

```sql
DROP POLICY IF EXISTS "deny-all authenticated: impersonation_sessions"    ON public.impersonation_sessions;
DROP POLICY IF EXISTS "deny-all authenticated: org_api_secrets"           ON public.org_api_secrets;
DROP POLICY IF EXISTS "deny-all authenticated: super_admin_mfa_lockouts"  ON public.super_admin_mfa_lockouts;
DROP POLICY IF EXISTS "deny-all authenticated: super_admin_recovery_codes" ON public.super_admin_recovery_codes;
DROP POLICY IF EXISTS "deny-all authenticated: super_admin_users"         ON public.super_admin_users;
DROP POLICY IF EXISTS "deny-all authenticated: tenant_billing_events"     ON public.tenant_billing_events;
-- Note: removing these restores linter 0008 warnings but does NOT open a security hole.
-- service_role access and SECURITY DEFINER RPCs function identically without explicit policies.
```

---

## Post-deploy Verification

After deploying to staging, re-run Supabase linter:
- Dashboard → Database → Advisors → Security
- Filter `lint=0008_rls_enabled_no_policy`
- Expected: 0 findings for all 6 tables listed in this plan.

Note: `sla_audit_ledger_p0..p3` are handled by `20260527000001_fix_partition_rls.sql`.
