# Test Plan — 20260717000003_fix_sensitive_table_anon_access

**Migration:** `supabase/migrations/20260717000003_fix_sensitive_table_anon_access.sql`
**Linter ID:** 0024 — `pg_graphql_anon_table_exposed`
**Risk:** Medium — ACL change, no RLS policy change. SECURITY DEFINER functions unaffected.

---

## Problem

Tables granted to `anon` are discoverable via the PostgREST schema cache and pg_graphql introspection even when RLS blocks all rows. For super admin tables and secrets tables, even column name enumeration is a security concern:
- `org_api_secrets` — schema reveals secret storage structure (INV-28)
- `super_admin_users` — reveals super admin registry existence
- `super_admin_tenant_health_view` / `super_admin_tenant_technical_health_view` — NO RLS; anon sees ALL tenant data

None of these tables are directly queried by the Flutter client or any anon-auth code path. All access is through SECURITY DEFINER RPCs (which run as `postgres` owner, bypassing role-level ACL).

---

## Affected Tables

| Table | RLS | Risk |
|-------|-----|------|
| `org_api_secrets` | Yes | Secret structure enumeration + potential data if policy regresses |
| `super_admin_users` | Yes | Registry existence enumeration |
| `super_admin_mfa_lockouts` | Yes | MFA state enumeration |
| `super_admin_recovery_codes` | Yes | Recovery code structure enumeration |
| `super_admin_access_log` | Yes | Audit trail enumeration |
| `impersonation_sessions` | Yes | Active session enumeration |
| `tenant_billing_events` | Yes | Billing structure + policy regression risk |
| `provider_api_keys` | Yes | API key structure enumeration |
| `super_admin_tenant_health_view` | **No** | **ALL tenant data exposed to anon** |
| `super_admin_tenant_technical_health_view` | **No** | **ALL tenant technical data exposed to anon** |

---

## Pre-migration Assertions

```sql
-- Confirm anon access exists before migration
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'org_api_secrets', 'super_admin_users', 'super_admin_mfa_lockouts',
    'super_admin_recovery_codes', 'super_admin_access_log',
    'impersonation_sessions', 'tenant_billing_events', 'provider_api_keys',
    'super_admin_tenant_health_view', 'super_admin_tenant_technical_health_view'
  )
  AND array_to_string(c.relacl, ',') LIKE '%anon=%'
ORDER BY c.relname;
-- Expected: 10 rows
```

---

## Post-migration Assertions

```sql
-- 1. No anon grant on any of the 10 targeted tables/views
SELECT c.relname, array_to_string(c.relacl, ',') AS acl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'org_api_secrets', 'super_admin_users', 'super_admin_mfa_lockouts',
    'super_admin_recovery_codes', 'super_admin_access_log',
    'impersonation_sessions', 'tenant_billing_events', 'provider_api_keys',
    'super_admin_tenant_health_view', 'super_admin_tenant_technical_health_view'
  )
  AND array_to_string(c.relacl, ',') LIKE '%anon=%'
ORDER BY c.relname;
-- Expected: 0 rows

-- 2. supabase_auth_admin SELECT grant on super_admin_users preserved
SELECT array_to_string(c.relacl, ',') AS acl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'super_admin_users';
-- Expected: ACL contains 'supabase_auth_admin=r/postgres'

-- 3. service_role and authenticated grants on tenant_billing_events preserved
SELECT array_to_string(c.relacl, ',') AS acl
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'tenant_billing_events';
-- Expected: ACL contains 'authenticated=' and 'service_role='

-- 4. SECURITY DEFINER RPC still works (run as part of make test-e2e):
-- super_admin_create_organization → writes to org_api_secrets (SECURITY DEFINER,
-- runs as postgres, bypasses anon ACL restriction). Must succeed.
```

---

## Application Impact Verification

```powershell
make test-e2e
```

Paths that touch the targeted tables via SECURITY DEFINER RPCs:
1. **Org creation** → writes `org_api_secrets` via `super_admin_create_organization`
2. **Super admin login** → reads `super_admin_users` via `custom_access_token_hook`
3. **Billing plan change** → writes `tenant_billing_events` via `super_admin_update_organization_quota`
4. **MFA challenge** → reads/writes `super_admin_mfa_lockouts` via MFA RPCs

All of the above run as SECURITY DEFINER (postgres owner) → unaffected by anon ACL revoke.

---

## Rollback

```sql
-- Re-grant if an unexpected path breaks:
GRANT ALL ON TABLE public.<table_name> TO anon;
```

For `super_admin_tenant_health_view` and `super_admin_tenant_technical_health_view`, investigate whether the view should have `WITH (security_invoker = true)` and RLS before re-granting to anon.
