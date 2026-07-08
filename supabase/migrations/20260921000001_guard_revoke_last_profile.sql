-- =============================================================================
-- Migration: 20260921000001_guard_revoke_last_profile.sql
-- Description: Blocks revocation of a member's last active profile.
--   A user with zero active tenant-role assignments is an undefined/unsafe
--   state: no permissions, no audit trail, potential stale-JWT drift (INV-22).
--   The guard raises P0001 (LastProfileGuard) AFTER the soft-revoke so that
--   the transaction auto-rolls back -- no partial state is persisted.
-- Invariants: INV-3 (append-only), INV-22 (tenant isolation), INV-26
-- =============================================================================

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
  v_org_id          uuid;
  v_has_sensitive   boolean;
  v_remaining_count int;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  PERFORM public._rbac_assert_can_manage_target(p_target_user);
  PERFORM public._rbac_assert_can_grant_role(p_role_id);
  v_org_id := public._rbac_caller_org_id();

  UPDATE public.user_tenant_roles
     SET revoked_at = NOW()
   WHERE user_id        = p_target_user
     AND tenant_role_id = p_role_id
     AND organization_id = v_org_id
     AND revoked_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Last-profile guard (INV-22): count remaining active assignments AFTER
  -- soft-revoke. Raising here auto-rolls back the UPDATE above atomically.
  SELECT COUNT(*)::int INTO v_remaining_count
    FROM public.user_tenant_roles
   WHERE user_id         = p_target_user
     AND organization_id = v_org_id
     AND revoked_at IS NULL
     AND (valid_until IS NULL OR valid_until > NOW());

  IF v_remaining_count = 0 THEN
    RAISE EXCEPTION 'LastProfileGuard: cannot remove the last active profile from a member'
      USING ERRCODE = 'P0001';
  END IF;

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

  UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = p_role_id;
  PERFORM public._rbac_sync_coarse_role_admin(p_target_user, v_org_id);

  PERFORM public._rbac_audit(
    'ROLE_REVOKED',
    jsonb_build_object('target_user', p_target_user, 'role_id', p_role_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO service_role;