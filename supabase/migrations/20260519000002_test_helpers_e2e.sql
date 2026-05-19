-- =============================================================================
-- E2E Test Helpers: SQL-based archive/ban state setup for integration tests
-- =============================================================================
-- WHY: _archiveOrgInDb in CT13 called GoTrue Admin REST API to ban users.
-- When ANY auth.users row has banned_until='infinity', GoTrue returns HTTP 500
-- on ALL /auth/v1/admin/users/* calls, making the test setup itself the
-- trigger for cascading failures. These SECURITY DEFINER functions bypass
-- GoTrue entirely, writing directly to auth.users (same path as the
-- production super_admin_archive_organization RPC).
--
-- INV-6: TIMESTAMPTZ sentinel '9999-12-31 23:59:59+00' — GoTrue-safe, finite.
-- INV-DB: DML only, no DDL locks.
-- INV-3: auth.users is NOT an append-only ledger — UPDATE is safe.
-- =============================================================================

-- ── Helper 1: Archive org + ban all member users in a single SQL round-trip ──
CREATE OR REPLACE FUNCTION public.test_archive_org_for_e2e(p_org_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  UPDATE organizations
  SET    status     = 'ARCHIVED',
         updated_at = NOW()
  WHERE  id = p_org_id
    AND  status <> 'ARCHIVED';

  UPDATE user_roles
  SET    is_active = false
  WHERE  organization_id = p_org_id;

  -- Same GoTrue-safe sentinel used by super_admin_archive_organization (INV-6)
  UPDATE auth.users
  SET    banned_until = '9999-12-31 23:59:59+00'::timestamptz
  WHERE  id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.test_archive_org_for_e2e(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.test_archive_org_for_e2e(UUID) TO service_role;

-- ── Helper 2: Read banned_until from auth.users without GoTrue REST API ──────
CREATE OR REPLACE FUNCTION public.test_get_user_banned_until(p_user_id UUID)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_banned_until TIMESTAMPTZ;
BEGIN
  SELECT banned_until
  INTO   v_banned_until
  FROM   auth.users
  WHERE  id = p_user_id;

  RETURN v_banned_until;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.test_get_user_banned_until(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.test_get_user_banned_until(UUID) TO service_role;
