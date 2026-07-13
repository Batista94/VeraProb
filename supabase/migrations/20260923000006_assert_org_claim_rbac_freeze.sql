-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: assert_org_claim helper + RBAC custom expansion freeze (PR6)
-- Shared JWT org claim check for SECURITY DEFINER RPCs — stop full-body clones.
-- Future patches: call assert_org_claim(p_org_id); do not paste claim blocks.
-- Invariants: INV-1, INV-2, INV-22.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.assert_org_claim(p_org_id UUID)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $$
DECLARE
  v_claims JSONB := auth.jwt();
  v_role   TEXT;
  v_org    TEXT;
BEGIN
  IF p_org_id IS NULL THEN
    RAISE EXCEPTION 'organization_id required'
      USING ERRCODE = '42501';
  END IF;

  -- service_role / missing JWT (DB tests as postgres) — allow.
  IF v_claims IS NULL THEN
    RETURN;
  END IF;

  v_role := v_claims ->> 'role';
  IF v_role IS NOT DISTINCT FROM 'service_role' THEN
    RETURN;
  END IF;

  v_org := v_claims -> 'app_metadata' ->> 'org_id';
  IF v_org IS DISTINCT FROM p_org_id::text THEN
    RAISE EXCEPTION 'not found'
      USING ERRCODE = '42501'; -- INV-26 anti-oracle
  END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_org_claim(UUID) IS
  'PR6: shared JWT app_metadata.org_id assert for RPCs. Prefer this over pasting claim blocks.';

REVOKE ALL ON FUNCTION public.assert_org_claim(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_org_claim(UUID) TO authenticated, service_role;

-- Freeze custom RBAC expansion (keep system roles + assignments).
COMMENT ON TABLE public.tenant_roles IS
  'FREEZE (PR6): no new custom-role product features until buyer demand. System roles + user_tenant_roles remain.';
COMMENT ON TABLE public.role_change_requests IS
  'FREEZE (PR6): dual-control role change queue — do not expand ABAC scope surface.';
COMMENT ON COLUMN public.tenant_permissions.is_scopable IS
  'FREEZE (PR6): ABAC-lite scope flag — do not grow scope vocabulary without product proof.';
