-- =============================================================================
-- Tier-S: Team Management & Archive Cascade
-- =============================================================================
-- A. user_roles.is_active column for soft-deactivation
-- B. Archive RPC cascade: deactivate all org users on archive
-- C. deactivate_member RPC for tenant-level team management
-- D. Update get_org_members to filter inactive users
--
-- INV-3: NO DROP of immutability rules. All operations are DDL-only.
-- INV-22: Tenant isolation enforced via JWT org_id in all RPCs.
-- =============================================================================

-- ── A. Add is_active column to user_roles ────────────────────────────────────

ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- ── B. Update archive RPC with user cascade ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.super_admin_archive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- INV-26: 404-parity — treat DELETED as non-existent
  IF NOT EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status <> 'DELETED'
  ) THEN
    RAISE EXCEPTION 'Not found' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency guard: already archived is a distinct error (P0003)
  IF EXISTS (
    SELECT 1 FROM organizations
    WHERE id = p_org_id AND status = 'ARCHIVED'
  ) THEN
    RAISE EXCEPTION 'Organization already archived' USING ERRCODE = 'P0003';
  END IF;

  -- Set status to ARCHIVED
  UPDATE organizations
  SET    status     = 'ARCHIVED',
         updated_at = NOW()
  WHERE  id = p_org_id;

  -- Revoke all active API secrets (INV-3: set revoked_at, never DELETE)
  UPDATE org_api_secrets
  SET    revoked_at = NOW(),
         rotated_at = NOW()
  WHERE  organization_id = p_org_id
    AND  revoked_at IS NULL;

  -- Cascade: deactivate all org users in user_roles
  UPDATE user_roles
  SET    is_active = false
  WHERE  organization_id = p_org_id;

  -- Cascade: ban all org users in auth.users (prevents login immediately)
  UPDATE auth.users
  SET    banned_until = 'infinity'
  WHERE  id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  -- Append-only audit record (INV-3)
  INSERT INTO system_audit_log
    (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES
    (
      'ORG_ARCHIVED',
      'warning',
      p_org_id,
      p_reason,
      'HUMAN',
      'rpc',
      jsonb_build_object(
        'super_admin_id', p_super_admin_id,
        'reason',         p_reason
      )
    );
END;
$$;

-- ── C. deactivate_member RPC ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.deactivate_member(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org   UUID;
  v_target_org   UUID;
  v_target_role  TEXT;
  v_admin_count  INT;
BEGIN
  -- Caller's org from JWT
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID;

  -- Target must be in same org and active
  SELECT organization_id, role INTO v_target_org, v_target_role
  FROM user_roles WHERE user_id = p_target_user_id AND is_active = true;

  IF NOT FOUND OR v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'P0002';
  END IF;

  -- Cannot deactivate self
  IF p_target_user_id = (auth.jwt() ->> 'sub')::uuid THEN
    RAISE EXCEPTION 'Cannot deactivate yourself' USING ERRCODE = 'P0001';
  END IF;

  -- Last-admin guard
  IF v_target_role = 'TENANT_ADMIN' THEN
    SELECT COUNT(*) INTO v_admin_count FROM user_roles
    WHERE organization_id = v_caller_org AND role = 'TENANT_ADMIN' AND is_active = true;
    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot deactivate the last administrator' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE user_roles SET is_active = false WHERE user_id = p_target_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_member(UUID) TO authenticated;

-- ── D. Update get_org_members to filter inactive users ───────────────────────

CREATE OR REPLACE FUNCTION public.get_org_members()
RETURNS TABLE (
  user_id       UUID,
  email         TEXT,
  role          TEXT,
  invited_at    TIMESTAMPTZ,
  last_sign_in  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: User does not belong to an organization';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email::text,
    ur.role::text,
    u.created_at AS invited_at,
    u.last_sign_in_at AS last_sign_in
  FROM auth.users u
  JOIN public.user_roles ur ON ur.user_id = u.id
  WHERE ur.organization_id = caller_org_id
    AND ur.is_active = true
  ORDER BY u.created_at DESC;
END;
$$;
