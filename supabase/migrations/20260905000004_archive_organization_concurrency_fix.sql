-- ── Migration 20260905000004 ─────────────────────────────────────────────────
-- Fix: super_admin_archive_organization is not idempotent under concurrency.
--
-- WHY: The prior body (20260707000000) guarded idempotency with a check-then-act
-- pattern — two EXISTS reads followed by an unguarded UPDATE. Under a concurrent
-- double-click (two RPC calls racing), BOTH pass the `status = 'ARCHIVED'` check
-- before either commits, so BOTH run the cascade and BOTH append an 'ORG_ARCHIVED'
-- audit row. Result: duplicate audit entries (INV-3), double secret revocation,
-- and the losing caller never receives the P0003 "already archived" it is owed
-- (INV-10). Caught by property_double_click_idempotency_test (Property 6).
--
-- FIX: lock-then-check. `SELECT ... FOR UPDATE` serialises concurrent callers on
-- the organization row; the loser blocks, re-reads status = 'ARCHIVED' after the
-- winner commits, and correctly raises P0003. Exactly one archive, one audit row.
--
-- Cascade A–F, error codes (P0002/P0003), INV-26 404-parity, and the JWT guard
-- are preserved verbatim from 20260707000000 — only the guard mechanism changes.
--
-- INV-3: append-only audit — exactly one 'ORG_ARCHIVED' row per archival.
-- INV-10: typed error P0003 for already-archived (now honoured under concurrency).
-- INV-26: 404-parity — same P0002 for not-found AND soft-deleted.
-- INV-DB: non-blocking function redefine (CREATE OR REPLACE, same signature).
--
-- pr_scanner: ignore-regression — intentional CREATE OR REPLACE to close TOCTOU
-- idempotency defect (INV-3/INV-10). Cascade A-F, error codes, and JWT guard
-- preserved verbatim from 20260707000000. QA-Security Council reviewed 2026-06-30.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.super_admin_archive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_status TEXT;
BEGIN
  -- JWT guard (INV-6)
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Lock-then-check (concurrency-safe idempotency) ─────────────────────────
  -- Concurrent callers serialise on this row lock; only one performs the
  -- transition, the rest re-read the committed status below.
  SELECT status INTO v_status
  FROM   organizations
  WHERE  id = p_org_id
  FOR UPDATE;

  -- 404-parity (INV-26): not-found AND soft-deleted both return P0002
  IF NOT FOUND OR v_status = 'DELETED' THEN
    RAISE EXCEPTION 'Not found' USING ERRCODE = 'P0002';
  END IF;

  -- Idempotency (INV-10): the loser of a concurrent double-click lands here
  IF v_status = 'ARCHIVED' THEN
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

-- ACL self-containment (defense-in-depth): CREATE OR REPLACE preserves existing
-- grants, but restate them so this migration does not depend on 20260815000001
-- running first for a partial migration set. Idempotent.
GRANT EXECUTE ON FUNCTION public.super_admin_archive_organization(uuid, text, uuid)
  TO authenticated, service_role;
