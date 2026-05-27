-- =============================================================================
-- Fix: pg_graphql_anon_table_exposed (Supabase linter 0024)
-- =============================================================================
-- REASON:
--   Even with RLS enabled, tables granted to `anon` are visible via the
--   PostgREST/pg_graphql API. An unauthenticated client can:
--     a) Enumerate column names, types, and constraints via schema introspection.
--     b) Potentially read rows if ANY policy matches (e.g. a future regression).
--
--   The tables targeted here are exclusively accessed through SECURITY DEFINER
--   RPCs or service_role calls. No client-side code references them directly.
--   SECURITY DEFINER functions execute as the owner (postgres), so they are
--   UNAFFECTED by removing anon-level table grants.
--
--   Impact on existing flows:
--   - super_admin_* RPCs:       SECURITY DEFINER → run as postgres → unaffected
--   - custom_access_token_hook: SECURITY DEFINER → run as postgres → unaffected
--   - MFA lockout RPCs:         SECURITY DEFINER → run as postgres → unaffected
--   - Flutter client:           Never queries these tables directly
--
-- INVARIANTS:
--   INV-2  — anon can no longer enumerate org secrets / super admin tables.
--   INV-22 — cross-tenant health views no longer exposed to unauthenticated.
--   INV-28 — org_api_secrets fully locked down: no anon read/write path.
-- =============================================================================

-- ── 1. org_api_secrets ───────────────────────────────────────────────────────
-- INV-28: per-org HMAC secrets. Already has RESTRICTIVE deny-all (migration
-- 20260716000001). Remove the ACL grant entirely to stop schema enumeration.
REVOKE ALL ON TABLE public.org_api_secrets FROM anon;

-- ── 2. super_admin_users ─────────────────────────────────────────────────────
-- Super admin registry. Read by supabase_auth_admin (kept via GRANT SELECT).
-- anon has no legitimate path to this table.
REVOKE ALL ON TABLE public.super_admin_users FROM anon;

-- ── 3. super_admin_mfa_lockouts ──────────────────────────────────────────────
-- MFA circuit-breaker state. Only SECURITY DEFINER RPCs may access.
REVOKE ALL ON TABLE public.super_admin_mfa_lockouts FROM anon;

-- ── 4. super_admin_recovery_codes ────────────────────────────────────────────
-- SHA-256 hashed MFA recovery codes. Only SECURITY DEFINER RPCs may access.
REVOKE ALL ON TABLE public.super_admin_recovery_codes FROM anon;

-- ── 5. super_admin_access_log ────────────────────────────────────────────────
-- Immutable super-admin access audit trail. Written by SECURITY DEFINER RPCs.
REVOKE ALL ON TABLE public.super_admin_access_log FROM anon;

-- ── 6. impersonation_sessions ────────────────────────────────────────────────
-- Active impersonation audit trail. Managed via SECURITY DEFINER RPCs.
REVOKE ALL ON TABLE public.impersonation_sessions FROM anon;

-- ── 7. tenant_billing_events ─────────────────────────────────────────────────
-- INV-3: immutable billing ledger. Written by SECURITY DEFINER RPCs only.
-- SuperAdmin reads via service_role dashboard.
REVOKE ALL ON TABLE public.tenant_billing_events FROM anon;

-- ── 8. provider_api_keys ─────────────────────────────────────────────────────
-- Per-org 3rd-party API keys. Only accessible by authenticated org members.
-- No anon flow needs direct table access; RPCs handle these.
REVOKE ALL ON TABLE public.provider_api_keys FROM anon;

-- ── 9. super_admin_tenant_health_view ────────────────────────────────────────
-- View exposing cross-tenant operational health. No RLS. Service_role only.
-- NOTE: This view has NO security_invoker — it is a SECURITY DEFINER view
-- that bypasses RLS and shows ALL tenants. anon access = full data exposure.
REVOKE ALL ON TABLE public.super_admin_tenant_health_view FROM anon;

-- ── 10. super_admin_tenant_technical_health_view ─────────────────────────────
-- Same risk as above: cross-tenant technical metrics, no RLS.
REVOKE ALL ON TABLE public.super_admin_tenant_technical_health_view FROM anon;

-- ── Verify (advisory) ─────────────────────────────────────────────────────────
-- SELECT c.relname, array_to_string(c.relacl, ',') AS acl
-- FROM pg_class c
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- WHERE n.nspname = 'public'
--   AND c.relname IN (
--     'org_api_secrets', 'super_admin_users', 'super_admin_mfa_lockouts',
--     'super_admin_recovery_codes', 'super_admin_access_log',
--     'impersonation_sessions', 'tenant_billing_events', 'provider_api_keys',
--     'super_admin_tenant_health_view', 'super_admin_tenant_technical_health_view'
--   )
-- ORDER BY c.relname;
-- Expected: no 'anon=' in the acl column for any row
