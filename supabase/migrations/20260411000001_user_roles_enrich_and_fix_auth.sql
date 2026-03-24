SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: 20260411000001 — Enrich user_roles + fix post-invite sign-in
--
-- Bug 1 (Auth): After accepting an invite via signUp, the created user's email
--   is not confirmed. Subsequent signInWithPassword calls fail with "invalid
--   credentials" even though the credentials are correct. Root cause: Supabase
--   Auth requires email_confirmed_at to be set, regardless of the local
--   enable_confirmations = false config flag, when the account was created via
--   signUp (not via invite link). Fix: auto-confirm in accept_invitation RPC.
--
-- Bug 2 (Schema): user_roles lacked user_email and organization_name columns.
--   These are required for traceability without JOINs (consistent with
--   organization_name already added to tenant_billing_events in 20260408000003).
--
-- Changes:
--   1. ADD COLUMN user_email TEXT to public.user_roles.
--   2. ADD COLUMN organization_name TEXT to public.user_roles.
--   3. CREATE OR REPLACE accept_invitation to:
--      a. Confirm the user's email in auth.users (fixes Bug 1).
--      b. Populate user_email + organization_name on INSERT/UPDATE.
-- =============================================================================

-- ── 1. Schema changes ────────────────────────────────────────────────────────

ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS user_email       TEXT,
  ADD COLUMN IF NOT EXISTS organization_name TEXT;

-- ── 2. Updated RPC ───────────────────────────────────────────────────────────

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
  v_inv       public.invitations%ROWTYPE;
  v_email     TEXT;
  v_org_name  TEXT;
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

  -- Resolve denormalized fields for traceability
  SELECT email INTO v_email
  FROM auth.users
  WHERE id = p_user_id;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = v_inv.organization_id;

  -- Bug 1 fix: ensure the user's email is confirmed so signInWithPassword
  -- succeeds on the next login attempt. COALESCE preserves any existing
  -- confirmation timestamp set by an email-link flow.
  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
      updated_at         = now()
  WHERE id = p_user_id;

  -- Mark invitation as accepted
  UPDATE public.invitations
  SET accepted_at_utc = now()
  WHERE id = v_inv.id;

  -- Upsert into user_roles (1-user-to-1-tenant model, PK on user_id)
  INSERT INTO public.user_roles (
    user_id,
    organization_id,
    role,
    user_email,
    organization_name
  )
  VALUES (
    p_user_id,
    v_inv.organization_id,
    v_inv.role,
    v_email,
    v_org_name
  )
  ON CONFLICT (user_id) DO UPDATE
  SET organization_id   = EXCLUDED.organization_id,
      role              = EXCLUDED.role,
      contractor_id     = NULL,
      user_email        = EXCLUDED.user_email,
      organization_name = EXCLUDED.organization_name;

END;
$$;

REVOKE ALL ON FUNCTION public.accept_invitation(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invitation(TEXT, UUID) TO anon, authenticated;
