-- ============================================================
-- veraprob — Fix accept_invitation RPC (Phase 9) — consolidated
-- ============================================================
-- REASON:
--   The original accept_invitation RPC attempted an upsert into
--   public.user_roles using ON CONFLICT (user_id, organization_id).
--   However, user_roles strictly enforces a 1-user-to-1-tenant
--   model via a PRIMARY KEY on (user_id). This mismatch caused a
--   42P10 exception when accepting invitations.
--
-- FIX 1 (original):
--   Update the ON CONFLICT clause to use (user_id) in line with
--   the domain architecture. We DO UPDATE to allow an invited user
--   to safely transition between organizations.
--
-- FIX 2 (regression introduced by this file):
--   This migration ran after 20260411000001 and overwrote the
--   accept_invitation function without the email-confirmation fix.
--   Supabase client-side signUp does NOT set email_confirmed_at
--   even when enable_confirmations = false in config.toml.
--   Subsequent signInWithPassword calls therefore fail with
--   "Invalid login credentials". Fix: force-confirm the email
--   inside the RPC (SECURITY DEFINER runs as postgres, which has
--   write access to auth.users).
--
-- FIX 3: populate user_email + organization_name columns that were
--   added by migration 20260411000001.
-- ============================================================

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
  v_inv      public.invitations%ROWTYPE;
  v_email    TEXT;
  v_org_name TEXT;
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

  -- Resolve denormalized fields for traceability (columns added by 20260411000001)
  SELECT email INTO v_email
  FROM auth.users
  WHERE id = p_user_id;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = v_inv.organization_id;

  -- FIX 2: confirm the user's email so signInWithPassword works after logout.
  -- Supabase client signUp does not set email_confirmed_at even when
  -- enable_confirmations = false. COALESCE preserves any existing timestamp.
  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
      updated_at         = now()
  WHERE id = p_user_id;

  -- Mark invitation as accepted
  UPDATE public.invitations
  SET accepted_at_utc = now()
  WHERE id = v_inv.id;

  -- Upsert into user_roles (1-user-to-1-tenant model, PK on user_id).
  -- FIX 1: ON CONFLICT (user_id) — not (user_id, organization_id).
  -- FIX 3: populate user_email + organization_name for traceability without JOIN.
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
