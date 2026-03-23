-- ============================================================
-- veraprob — Fix accept_invitation RPC (Phase 9)
-- ============================================================
-- REASON:
--   The original accept_invitation RPC attempted an upsert into
--   public.user_roles using ON CONFLICT (user_id, organization_id).
--   However, user_roles strictly enforces a 1-user-to-1-tenant
--   model via a PRIMARY KEY on (user_id). This mismatch caused a
--   42P10 exception when accepting invitations.
--
-- FIX:
--   Update the ON CONFLICT clause to use (user_id) perfectly in
--   line with the domain architecture. We DO UPDATE to allow an
--   invited user to safely transition between organizations.
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

  -- Upsert user into user_roles safely adhering to 1-user-to-1-tenant
  -- contractor_id is set to NULL because invitations are for internal roles only
  INSERT INTO public.user_roles (user_id, organization_id, role)
  VALUES (p_user_id, v_inv.organization_id, v_inv.role)
  ON CONFLICT (user_id) DO UPDATE 
  SET organization_id = EXCLUDED.organization_id,
      role = EXCLUDED.role,
      contractor_id = NULL;

END;
$$;

REVOKE ALL ON FUNCTION public.accept_invitation(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invitation(TEXT, UUID) TO anon, authenticated;
