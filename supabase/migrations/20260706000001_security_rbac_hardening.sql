-- =============================================================================
-- Tier-S Security: RBAC Hardening (FIX-01)
-- =============================================================================
-- Adds JWT super_admin claim verification to archive/unarchive RPCs.
-- Ensures only verified SuperAdmins can perform these destructive lifecycle 
-- operations, even if they have an authenticated session.
-- =============================================================================

-- 1. Hardening super_admin_archive_organization
CREATE OR REPLACE FUNCTION public.super_admin_archive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- FIX-01: JWT guard (prohibits bypass via direct RPC call with valid non-SA JWT)
  IF auth.uid() IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- INV-26: 404-parity — treat DELETED as non-existent
  IF NOT EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status <> 'DELETED'
  ) THEN
    RAISE EXCEPTION 'Not found' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency guard
  IF EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status = 'ARCHIVED'
  ) THEN
    RAISE EXCEPTION 'Organization already archived' USING ERRCODE = 'P0003';
  END IF;

  UPDATE organizations
  SET    status     = 'ARCHIVED',
         updated_at = NOW()
  WHERE  id = p_org_id;

  -- Revoke secrets (INV-3)
  UPDATE org_api_secrets
  SET    revoked_at = NOW(),
         rotated_at = NOW()
  WHERE  organization_id = p_org_id
    AND  revoked_at IS NULL;

  UPDATE user_roles SET is_active = false WHERE organization_id = p_org_id;

  UPDATE auth.users
  SET    banned_until = 'infinity'
  WHERE  id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  INSERT INTO system_audit_log
    (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES
    ('ORG_ARCHIVED', 'warning', p_org_id, p_reason, 'HUMAN', 'rpc', 
     jsonb_build_object('super_admin_id', p_super_admin_id, 'reason', p_reason));
END;
$$;

-- 2. Hardening super_admin_unarchive_organization
CREATE OR REPLACE FUNCTION public.super_admin_unarchive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- FIX-01: JWT guard
  IF auth.uid() IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = p_org_id AND status = 'ARCHIVED') THEN
    RAISE EXCEPTION 'Organization not archived' USING ERRCODE = 'P0003';
  END IF;

  UPDATE organizations SET status = 'ACTIVE', updated_at = NOW() WHERE id = p_org_id;

  UPDATE user_roles SET is_active = true WHERE organization_id = p_org_id;

  UPDATE auth.users SET banned_until = NULL 
   WHERE id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  INSERT INTO system_audit_log (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES ('ORG_UNARCHIVED', 'info', p_org_id, p_reason, 'HUMAN', 'rpc', 
          jsonb_build_object('super_admin_id', p_super_admin_id, 'reason', p_reason));
END;
$$;
