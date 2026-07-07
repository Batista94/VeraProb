-- =============================================================================
-- Migration: 20260910000003 — Auto-kill sessions on sensitive role revocation (Pilar 1.5.B)
--
-- Extends revoke_tenant_role: after soft-revoking a user's role, checks whether
-- that role contains any is_sensitive permission. If so, calls
-- revoke_user_sessions(p_target_user) to immediately invalidate all refresh
-- tokens, closing the staleness window for sensitive operations.
--
-- Without this, a revoked user could obtain new access tokens (up to TTL=300s)
-- that still carry the sensitive claim. The live-check in approve_sanction /
-- reject_sanction blocks DB mutations, but route-level reads would remain valid.
-- Auto-kill eliminates the residual window for sensitive role removals.
--
-- Invariants: INV-1, INV-10, INV-21, INV-22.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.revoke_tenant_role(
  p_target_user uuid,
  p_role_id     uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
  v_org_id        uuid;
  v_has_sensitive boolean;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  v_org_id := public._rbac_caller_org_id();

  -- Soft-revoke the user's grant (append-only, INV-3).
  UPDATE public.user_tenant_roles
     SET revoked_at = NOW()
   WHERE user_id         = p_target_user
     AND tenant_role_id  = p_role_id
     AND organization_id = v_org_id
     AND revoked_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = p_role_id;

  PERFORM public._rbac_audit(
    'ROLE_REVOKED',
    jsonb_build_object('target_user', p_target_user, 'role_id', p_role_id)
  );

  -- Auto-kill: if the revoked role holds any sensitive permission, immediately
  -- invalidate all refresh tokens so the user cannot renew stale access tokens.
  -- revoke_user_sessions writes its own SESSIONS_REVOKED audit row (INV-21).
  SELECT EXISTS (
    SELECT 1
      FROM public.tenant_role_permissions trp
      JOIN public.tenant_permissions tp ON tp.key = trp.permission_key
     WHERE trp.tenant_role_id = p_role_id
       AND tp.is_sensitive
  ) INTO v_has_sensitive;

  IF v_has_sensitive THEN
    PERFORM public.revoke_user_sessions(p_target_user);
  END IF;
END;
$$;

-- Grants unchanged from 20260909000004.
REVOKE ALL ON FUNCTION public.revoke_tenant_role(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO authenticated;

RESET client_min_messages;
