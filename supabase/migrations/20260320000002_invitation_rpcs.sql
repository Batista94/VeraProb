-- ============================================================
-- veraprob — Phase 6: User Invitation RPCs
-- ============================================================
-- REASON:
--   Implements the three server-side functions for the invitation
--   lifecycle: invite_user, accept_invitation, revoke_invitation.
--
--   Also fixes the unique constraint on invitations to allow
--   re-inviting the same email after expiry or revocation.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Fix unique constraint from 20260320000001_invitations.sql
--    Replace table-level UNIQUE with a partial unique index
--    scoped only to ACTIVE (pending) invitations.
-- ------------------------------------------------------------
ALTER TABLE public.invitations
  DROP CONSTRAINT IF EXISTS uq_invitation_email_per_org;

-- Only one ACTIVE invite per email per org — expired/revoked/accepted do not count.
CREATE UNIQUE INDEX uq_active_invitation_email_per_org
  ON public.invitations (organization_id, email)
  WHERE accepted_at_utc IS NULL AND revoked_at_utc IS NULL;

-- ------------------------------------------------------------
-- 2. RPC: invite_user
--    Atomically revokes any existing pending invite for the email
--    and inserts a new one. IDs and token are generated in Dart
--    (Invariant 7: Deterministic Replay).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invite_user(
  p_email         TEXT,
  p_role          TEXT,
  p_token         TEXT,
  p_expires_at    TIMESTAMPTZ,
  p_invitation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
  caller_role   TEXT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required to invite users';
  END IF;

  IF p_role NOT IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be TENANT_ADMIN, OPERATOR, or AUDITOR', p_role;
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email cannot be empty';
  END IF;

  -- Revoke any existing pending invitation for this email in this org
  UPDATE public.invitations
  SET revoked_at_utc = now()
  WHERE organization_id = caller_org_id
    AND email           = lower(trim(p_email))
    AND accepted_at_utc IS NULL
    AND revoked_at_utc  IS NULL;

  -- Insert the new invitation
  INSERT INTO public.invitations (
    id,
    organization_id,
    email,
    role,
    token,
    invited_by,
    expires_at_utc
  )
  VALUES (
    p_invitation_id,
    caller_org_id,
    lower(trim(p_email)),
    p_role,
    p_token,
    auth.uid(),
    p_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) TO authenticated;

-- ------------------------------------------------------------
-- 3. RPC: accept_invitation
--    Public operation — authenticated by token possession alone.
--    Atomically validates the token, marks it accepted, and
--    inserts the user into user_roles.
--    GRANT to both anon and authenticated: the accepting user
--    may not have a user_roles row yet (newly signed up).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.accept_invitation(
  p_token   TEXT,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_inv public.invitations%ROWTYPE;
BEGIN
  IF p_token IS NULL OR trim(p_token) = '' THEN
    RAISE EXCEPTION 'Token cannot be empty';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID cannot be null';
  END IF;

  -- Lock the invitation row to prevent double-acceptance (race condition)
  SELECT * INTO v_inv
  FROM public.invitations
  WHERE token           = p_token
    AND accepted_at_utc IS NULL
    AND revoked_at_utc  IS NULL
    AND expires_at_utc  > now()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found, expired, revoked, or already accepted';
  END IF;

  -- Mark as accepted
  UPDATE public.invitations
  SET accepted_at_utc = now()
  WHERE id = v_inv.id;

  -- Upsert user into user_roles (idempotent)
  INSERT INTO public.user_roles (user_id, organization_id, role)
  VALUES (p_user_id, v_inv.organization_id, v_inv.role)
  ON CONFLICT (user_id, organization_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_invitation(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invitation(TEXT, UUID) TO anon, authenticated;

-- ------------------------------------------------------------
-- 4. RPC: revoke_invitation
--    Revokes a PENDING invitation. Cannot revoke accepted ones.
--    Server-side validates caller org + admin role.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_invitation(
  p_invitation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
  caller_role   TEXT;
  rows_updated  INT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required to revoke invitations';
  END IF;

  UPDATE public.invitations
  SET revoked_at_utc = now()
  WHERE id            = p_invitation_id
    AND organization_id = caller_org_id
    AND accepted_at_utc IS NULL
    AND revoked_at_utc  IS NULL;

  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  IF rows_updated = 0 THEN
    RAISE EXCEPTION 'Invitation not found, already accepted, or already revoked in this organization';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_invitation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_invitation(UUID) TO authenticated;
