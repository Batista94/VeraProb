-- Migration: 20260417000001_super_admin_proxy_rls
-- Phase 9.6.A.1 — Edge Proxy Security Hardening
--
-- Removes direct authenticated-role access to the super_admin tenant health
-- view. All reads must now go through the `super-admin-proxy` Edge Function
-- which holds SUPABASE_SERVICE_ROLE_KEY in Deno.env (INV-3, INV-14).
--
-- Also adds organization_id column to system_audit_log for per-tenant
-- filtering via the proxy, and creates the super_admin_access_log table
-- (append-only, INV-7) for justified impersonation audit trail.

-- ── 1. Revoke direct authenticated access to the tenant health view ───────────

REVOKE SELECT ON public.super_admin_tenant_health_view FROM authenticated;
GRANT SELECT ON public.super_admin_tenant_health_view TO service_role;

-- ── 2. Add organization_id to system_audit_log for per-tenant filtering ───────

ALTER TABLE public.system_audit_log
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id);

CREATE INDEX IF NOT EXISTS idx_system_audit_log_org
  ON public.system_audit_log (organization_id, occurred_at DESC)
  WHERE organization_id IS NOT NULL;

-- ── 3. Create super_admin_access_log (append-only audit trail, INV-7) ─────────

CREATE TABLE IF NOT EXISTS public.super_admin_access_log (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  caller_user_id  UUID        NOT NULL,
  action          TEXT        NOT NULL,
  ticket_id       TEXT        NOT NULL,
  justification   TEXT        NOT NULL DEFAULT '',
  target_org_id   UUID        REFERENCES public.organizations(id),
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_address      TEXT,
  request_params  JSONB
);

ALTER TABLE public.super_admin_access_log ENABLE ROW LEVEL SECURITY;

-- Append-only: no mutations allowed (INV-7 Immutable Ledger pattern).
CREATE RULE super_admin_access_log_no_update
  AS ON UPDATE TO public.super_admin_access_log DO INSTEAD NOTHING;

CREATE RULE super_admin_access_log_no_delete
  AS ON DELETE TO public.super_admin_access_log DO INSTEAD NOTHING;

-- Service_role can insert (Edge Function writes the log).
-- No authenticated role can read directly (all reads via proxy).
CREATE POLICY super_admin_access_log_service_insert
  ON public.super_admin_access_log
  FOR INSERT
  TO service_role
  WITH CHECK (true);
