-- =============================================================================
-- Fix: RLS-enabled tables with no policies (Supabase linter 0008)
-- =============================================================================
-- REASON:
--   Supabase dashboard linter flags every table where RLS is enabled but
--   zero policies exist. These 6 tables are intentionally service_role-only:
--   authenticated users must NEVER access them. The implicit deny-all
--   (no policies = no access) is correct but silent — the linter cannot
--   distinguish intentional emptiness from a forgotten policy.
--
--   This migration adds explicit RESTRICTIVE USING(false) policies so:
--     a) The linter is satisfied.
--     b) Future maintainers see explicit intent, not absence.
--     c) Even if a permissive policy is accidentally added later,
--        the RESTRICTIVE policy seals the table.
--
--   Service-role key BYPASSES RLS regardless of policies, so all existing
--   Edge Functions and SECURITY DEFINER RPCs continue to work unchanged.
--
-- INVARIANTS:
--   INV-2  — RLS: no authenticated path to these tables.
--   INV-22 — Tenant-A NEVER sees Tenant-B. These tables have no org filter
--             because authenticated users must never reach them at all.
--   INV-28 — org_api_secrets NEVER exposed via RLS.
-- =============================================================================

-- ── 1. impersonation_sessions ────────────────────────────────────────────────
-- Managed exclusively via service_role Edge Functions.
-- SuperAdmin audit trail — authenticated users have zero access.
DROP POLICY IF EXISTS "deny-all authenticated: impersonation_sessions"
  ON public.impersonation_sessions;

CREATE POLICY "deny-all authenticated: impersonation_sessions"
  ON public.impersonation_sessions
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

-- ── 2. org_api_secrets ───────────────────────────────────────────────────────
-- INV-28: Per-org HMAC secrets. NEVER expose via client-side RLS.
-- Only service_role can read/write. Plain-text never stored.
DROP POLICY IF EXISTS "deny-all authenticated: org_api_secrets"
  ON public.org_api_secrets;

CREATE POLICY "deny-all authenticated: org_api_secrets"
  ON public.org_api_secrets
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

-- ── 3. super_admin_mfa_lockouts ──────────────────────────────────────────────
-- MFA circuit-breaker state. Only SECURITY DEFINER RPCs
-- (record_mfa_failure, reset_mfa_lockout, check_mfa_lockout) may access this.
DROP POLICY IF EXISTS "deny-all authenticated: super_admin_mfa_lockouts"
  ON public.super_admin_mfa_lockouts;

CREATE POLICY "deny-all authenticated: super_admin_mfa_lockouts"
  ON public.super_admin_mfa_lockouts
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

-- ── 4. super_admin_recovery_codes ───────────────────────────────────────────
-- SHA-256 hashed MFA recovery codes. SECURITY DEFINER RPCs only.
DROP POLICY IF EXISTS "deny-all authenticated: super_admin_recovery_codes"
  ON public.super_admin_recovery_codes;

CREATE POLICY "deny-all authenticated: super_admin_recovery_codes"
  ON public.super_admin_recovery_codes
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

-- ── 5. super_admin_users ─────────────────────────────────────────────────────
-- SuperAdmin user registry. Read by supabase_auth_admin (JWT hook) via
-- GRANT SELECT (not RLS). authenticated role has zero access.
DROP POLICY IF EXISTS "deny-all authenticated: super_admin_users"
  ON public.super_admin_users;

CREATE POLICY "deny-all authenticated: super_admin_users"
  ON public.super_admin_users
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);

-- ── 6. tenant_billing_events ─────────────────────────────────────────────────
-- Immutable billing ledger (INV-3). Written by SECURITY DEFINER RPCs only.
-- SuperAdmin reads via service_role dashboard, not via client RLS.
DROP POLICY IF EXISTS "deny-all authenticated: tenant_billing_events"
  ON public.tenant_billing_events;

CREATE POLICY "deny-all authenticated: tenant_billing_events"
  ON public.tenant_billing_events
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (false)
  WITH CHECK (false);
