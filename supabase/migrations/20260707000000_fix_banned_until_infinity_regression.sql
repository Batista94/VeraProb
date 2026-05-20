-- ── Migration 20260707000000 ─────────────────────────────────────────────────
-- Fix: Re-apply GoTrue-compatible banned_until sentinel value (Bug Regression)
--
-- WHY: The migration 20260706000005_fix_archive_impersonation_column.sql
-- accidentally re-introduced banned_until = 'infinity' which crashes GoTrue
-- and breaks SuperAdmin.
-- This migration re-applies the '9999-12-31 23:59:59+00'::timestamptz sentinel.
--
-- INV-3: auth.users is NOT append-only financial ledger — UPDATE is safe.
-- INV-6: TIMESTAMPTZ is used.
-- INV-DB: Non-blocking DML and function redefine.
-- ─────────────────────────────────────────────────────────────────────────────

-- Repair any infinity rows that might have been created
UPDATE auth.users
SET    banned_until = '9999-12-31 23:59:59+00'::timestamptz
WHERE  banned_until = 'infinity'::timestamptz;

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
  SET    banned_until = '9999-12-31 23:59:59+00'::timestamptz
  WHERE  id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  -- ── D. Cascade: Pending Invitations (SAFE TO DELETE/REVOKE) ───────────────
  UPDATE invitations
  SET    revoked_at_utc = NOW()
  WHERE  organization_id = p_org_id
    AND  accepted_at_utc IS NULL
    AND  revoked_at_utc IS NULL;

  -- ── E. Cascade: Active Impersonation Sessions ──────────────────────────────
  UPDATE impersonation_sessions
  SET    revoked_at = NOW()
  WHERE  target_org_id = p_org_id
    AND  revoked_at IS NULL;

  -- ── F. Audit Log ───────────────────────────────────────────────────────────
  INSERT INTO system_audit_log
    (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES
    ('ORG_ARCHIVED', 'warning', p_org_id, p_reason, 'HUMAN', 'rpc',
     jsonb_build_object(
       'super_admin_id', (auth.jwt() ->> 'sub')::uuid,
       'reason', p_reason,
       'cascade_count', (SELECT count(*) FROM user_roles WHERE organization_id = p_org_id)
     ));
END;
$$;
