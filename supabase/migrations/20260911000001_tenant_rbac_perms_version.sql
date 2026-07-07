-- pr_scanner: ignore-regression — new RPC + publication-membership only, INV-22 RLS-gated; QA/Security + Lead Reviewer Council (Pilar 2 plan)
-- =============================================================================
-- Migration: 20260911000001 — Permissions version source for client staleness
-- detection (Pilar 2 ADJ-1)
--
-- Closes the client-facing gap: the perms_v listener needs a deterministic,
-- authoritative source to compare the JWT's app_metadata.perms_v against, and a
-- push trigger for near-instant convergence.
--
--   1. current_perms_v() — SECURITY DEFINER STABLE, mirrors the JWT hook's exact
--      perms_v aggregate (max(tenant_roles.updated_at) epoch over the caller's
--      active, non-expired, non-revoked roles). Returns 0 for wildcard holders
--      (TENANT_ADMIN / SuperAdmin) — parity with the hook. Catches ALL change
--      types, including permission-matrix edits that don't touch user_tenant_roles.
--   2. Publish user_tenant_roles on supabase_realtime — scoped push for
--      assign/revoke. Realtime postgres_changes for `authenticated` is gated by
--      the table's org-scoped RLS (20260909000001), so Tenant-A never receives
--      Tenant-B events (INV-22). Membership only — no schema change.
--
-- Invariants: INV-1, INV-2, INV-6, INV-22.
-- Append-only: new function + idempotent publication ADD → types unchanged.
-- Depends on: 20260909000001 (schema + RLS), 20260909000002 (hook), 20260909000003 (has_permission).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── current_perms_v() — authoritative version tag (mirrors hook aggregate) ────
-- Behaviour:
--   • has_permission('*')  → 0 (wildcard admins never change; parity with hook)
--   • missing sub / org_id → 0 (no active tenant RBAC context)
--   • otherwise            → max(tenant_roles.updated_at) epoch over active roles
CREATE OR REPLACE FUNCTION public.current_perms_v()
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_org_id  uuid;
  v_perms_v bigint;
BEGIN
  IF public.has_permission('*') THEN
    RETURN 0;
  END IF;

  v_user_id := (auth.jwt() ->> 'sub')::uuid;
  v_org_id  := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;

  IF v_user_id IS NULL OR v_org_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(EXTRACT(EPOCH FROM MAX(tr.updated_at))::bigint, 0)
    INTO v_perms_v
    FROM public.user_tenant_roles utr
    JOIN public.tenant_roles tr
      ON tr.id = utr.tenant_role_id
     AND tr.deleted_at IS NULL
   WHERE utr.user_id         = v_user_id
     AND utr.organization_id = v_org_id
     AND utr.revoked_at IS NULL
     AND utr.valid_from <= NOW()
     AND (utr.valid_until IS NULL OR utr.valid_until > NOW());

  RETURN v_perms_v;
END;
$$;

REVOKE ALL ON FUNCTION public.current_perms_v() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_perms_v() TO authenticated, service_role;

-- ── Publish user_tenant_roles for scoped Realtime push (RLS-gated, INV-22) ────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_publication_tables
     WHERE pubname    = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename  = 'user_tenant_roles'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.user_tenant_roles;
  END IF;
END;
$$;

RESET client_min_messages;
