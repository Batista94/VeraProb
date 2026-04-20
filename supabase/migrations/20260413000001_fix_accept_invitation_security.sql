-- ============================================================
-- veraprob — Fix accept_invitation RPC — Security Hardening
-- ============================================================
-- BLOCKERS ADDRESSED (hostile-defense-attorney audit 2026-03-24):
--
-- BLOCKER-1: No email validation — an anon caller with a valid token
--   could call accept_invitation(token, victim_uuid) to confirm the
--   email and enroll an arbitrary user in the inviting org.
--   FIX: Validate v_email = v_inv.email before any mutation. Also pin
--   the UPDATE auth.users WHERE clause to AND email = v_inv.email for
--   defense-in-depth against TOCTOU.
--
-- BLOCKER-2: ON CONFLICT DO UPDATE set organization_id allowed silent
--   org-switch for already-enrolled users, poisoning the JWT claim
--   pipeline (INV-10). Org transfer is an audited admin operation,
--   not a side-effect of invitation acceptance.
--   FIX: Guard against cross-org conflict — raise exception if
--   p_user_id already belongs to a different org. Remove
--   organization_id from the DO UPDATE set list.
--
-- BLOCKER-3: contractor_id = NULL on conflict zeroed out the
--   contractor association for an existing CONTRACTOR_VIEWER, breaking
--   INV-20 (Dual-Key Isolation) silently.
--   FIX: Remove contractor_id from the DO UPDATE set list entirely.
--   Contractor association is managed via a dedicated, audited RPC.
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
  v_inv           public.invitations%ROWTYPE;
  v_email         TEXT;
  v_org_name      TEXT;
  v_existing_org  UUID;
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

  -- Resolve email for validation and traceability
  SELECT email INTO v_email
  FROM auth.users
  WHERE id = p_user_id;

  -- BLOCKER-1 FIX: verify the accepting user's email matches the invitation recipient.
  -- Prevents any caller (including anon) from enrolling an arbitrary user via token.
  IF v_email IS DISTINCT FROM v_inv.email THEN
    RAISE EXCEPTION 'User email does not match invitation recipient';
  END IF;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = v_inv.organization_id;

  -- BLOCKER-2 FIX: prevent silent org-switch for already-enrolled users.
  -- Org transfers require an explicit, audited admin operation — not a side-effect
  -- of invitation acceptance. This protects INV-10 (JWT claim integrity).
  SELECT organization_id INTO v_existing_org
  FROM public.user_roles
  WHERE user_id = p_user_id;

  IF FOUND AND v_existing_org IS DISTINCT FROM v_inv.organization_id THEN
    RAISE EXCEPTION
      'User is already a member of a different organization. '
      'Org transfer requires explicit admin authorization.';
  END IF;

  -- Confirm the user email so signInWithPassword works after logout.
  -- WHERE clause pins to verified email for TOCTOU defense (BLOCKER-1 defense-in-depth).
  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
      updated_at         = now()
  WHERE id    = p_user_id
    AND email = v_inv.email;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'User email mismatch at auth.users update — TOCTOU guard triggered, aborting';
  END IF;

  -- Mark invitation as accepted
  UPDATE public.invitations
  SET accepted_at_utc = now()
  WHERE id = v_inv.id;

  -- Upsert into user_roles.
  -- ON CONFLICT is safe: the cross-org guard above ensures the conflict (if any)
  -- is for the same org (re-invitation to upgrade/change role within same org).
  --
  -- BLOCKER-2 FIX: organization_id is NOT in the DO UPDATE set — it is guaranteed
  -- correct by the guard above and must never be silently overwritten here.
  --
  -- BLOCKER-3 FIX: contractor_id is NOT in the DO UPDATE set — retaining the
  -- existing contractor association. Changing contractor_id requires a dedicated
  -- audited RPC (INV-20 Dual-Key Isolation).
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
  SET role              = EXCLUDED.role,
      user_email        = EXCLUDED.user_email,
      organization_name = EXCLUDED.organization_name;

END;
$$;

REVOKE ALL ON FUNCTION public.accept_invitation(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invitation(TEXT, UUID) TO anon, authenticated;
