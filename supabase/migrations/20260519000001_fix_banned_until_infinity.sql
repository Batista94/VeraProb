-- =============================================================================
-- Fix: Replace PostgreSQL 'infinity' TIMESTAMPTZ with a finite sentinel value
-- =============================================================================
-- WHY: PostgreSQL accepts 'infinity' as a valid TIMESTAMPTZ literal, but GoTrue
-- (the Go-based auth server bundled with Supabase) uses time.Time internally,
-- which cannot parse the 'infinity' literal. When any row in auth.users has
-- banned_until = 'infinity', GoTrue returns HTTP 500 with
-- {"message":"Database error finding users"} on ALL /auth/v1/admin/users
-- listing calls.
--
-- This breaks the test helper _ensureUser: when a 422 (user already exists) is
-- returned, the helper calls GET /auth/v1/admin/users?email=... to look up the
-- existing user ID. With GoTrue returning HTTP 500, the response body is
-- {"message":"..."} (no 'users' key), and the cast to List<dynamic> throws:
--   type 'Null' is not a subtype of type 'List<dynamic>' in type cast
--
-- FAILING TESTS:
--   - test/integration/rls_isolation_test.dart
--   - test/integration/jwt_hook_e2e_test.dart
--
-- FIX: Replace all existing 'infinity' rows with the finite sentinel value
-- '9999-12-31 23:59:59+00', and redeclare super_admin_archive_organization
-- to use the same sentinel so future archive calls do not re-introduce the bug.
--
-- INV-3: auth.users is NOT an append-only financial ledger — UPDATE is safe.
-- INV-6: TIMESTAMPTZ is used throughout; bare TIMESTAMP is not introduced.
-- INV-DB: This is a non-blocking DML UPDATE on a small table (no DDL locks).
-- =============================================================================

-- ── Step 1: Repair all existing rows poisoned with 'infinity' ─────────────────
UPDATE auth.users
SET    banned_until = '9999-12-31 23:59:59+00'::timestamptz
WHERE  banned_until = 'infinity'::timestamptz;

-- ── Step 2: Redeclare archive RPC with GoTrue-compatible sentinel value ────────
-- Exact copy of the function body from
-- 20260706000005_fix_archive_impersonation_column.sql, changing only the
-- single 'infinity' literal in step C to '9999-12-31 23:59:59+00'::timestamptz.
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
  -- FIX: was 'infinity'; GoTrue (time.Time) cannot parse 'infinity', causing
  -- HTTP 500 on all /auth/v1/admin/users listing calls.
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
  -- Column name is target_org_id (corrected in 20260706000005).
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
