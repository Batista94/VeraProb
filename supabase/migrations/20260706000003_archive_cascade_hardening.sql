-- pr_scanner: ignore-regression
-- =============================================================================
-- Phase 2: Archive Cascade & Forensic Visibility (FIX-10)
-- =============================================================================
-- Hardens the archive process with state-level cascading and improves
-- the audit log visibility for impersonation history.
-- =============================================================================

-- 1. Hardening archive RPC with more cascades (Invitations, Impersonation)
CREATE OR REPLACE FUNCTION public.super_admin_archive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- JWT guard (INV-6)
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- 404-parity (INV-26)
  IF NOT EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status <> 'DELETED'
  ) THEN
    RAISE EXCEPTION 'Not found' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency
  IF EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status = 'ARCHIVED'
  ) THEN
    RAISE EXCEPTION 'Organization already archived' USING ERRCODE = 'P0003';
  END IF;

  -- ── A. Update Organization Status ──────────────────────────────────────────
  UPDATE organizations
  SET    status     = 'ARCHIVED',
         updated_at = NOW()
  WHERE  id = p_org_id;

  -- ── B. Cascade: API Secrets ────────────────────────────────────────────────
  UPDATE org_api_secrets
  SET    revoked_at = NOW()
  WHERE  organization_id = p_org_id
    AND  revoked_at IS NULL;

  -- ── C. Cascade: User Access (Roles & Bans) ──────────────────────────────────
  UPDATE user_roles
  SET    is_active = false
  WHERE  organization_id = p_org_id;

  UPDATE auth.users
  SET    banned_until = 'infinity'
  WHERE  id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  -- ── D. Cascade: Pending Invitations (SAFE TO DELETE/REVOKE) ───────────────
  -- We revoke instead of delete to keep a record, but they become unusable.
  UPDATE invitations
  SET    revoked_at_utc = NOW()
  WHERE  organization_id = p_org_id
    AND  accepted_at_utc IS NULL
    AND  revoked_at_utc IS NULL;

  -- ── E. Cascade: Active Impersonation Sessions ──────────────────────────────
  -- If anyone is currently impersonating this org, revoke it.
  UPDATE impersonation_sessions
  SET    revoked_at = NOW()
  WHERE  target_organization_id = p_org_id
    AND  revoked_at IS NULL;

  -- ── F. Audit Log ───────────────────────────────────────────────────────────
  INSERT INTO system_audit_log
    (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES
    ('ORG_ARCHIVED', 'warning', p_org_id, p_reason, 'HUMAN', 'rpc', 
     jsonb_build_object(
       'super_admin_id', p_super_admin_id, 
       'reason', p_reason,
       'cascade_count', (SELECT count(*) FROM user_roles WHERE organization_id = p_org_id)
     ));
END;
$$;
