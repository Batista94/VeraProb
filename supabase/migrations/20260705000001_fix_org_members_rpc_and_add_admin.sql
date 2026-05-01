-- ============================================================
-- Migration: fix_org_members_rpc_and_add_admin
-- Fixes:
--   1. super_admin_get_org_members: previously only returned users
--      who had already accepted their invitation (JOIN user_roles).
--      Now uses UNION with invitations to show pending invites too.
--   2. Adds super_admin_add_org_admin RPC for CT06: adding a new
--      admin to an existing organization.
-- ============================================================

-- ── 1. Fix super_admin_get_org_members ───────────────────────
--
-- Must DROP first because PostgreSQL forbids changing return type with
-- CREATE OR REPLACE when adding a new column (status text).
--
DROP FUNCTION IF EXISTS public.super_admin_get_org_members(uuid);

CREATE OR REPLACE FUNCTION public.super_admin_get_org_members(p_org_id uuid)
RETURNS TABLE(
  user_id     uuid,
  email       text,
  role        text,
  invited_at  timestamp with time zone,
  last_sign_in timestamp with time zone,
  is_active   boolean,
  status      text    -- 'active' | 'pending' | 'inactive'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
BEGIN
  -- JWT guard: only super_admin may call this.
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Accepted members (have user_roles row)
  RETURN QUERY
  SELECT
    u.id            AS user_id,
    u.email::text   AS email,
    ur.role::text   AS role,
    u.created_at    AS invited_at,
    u.last_sign_in_at AS last_sign_in,
    ur.is_active    AS is_active,
    CASE WHEN ur.is_active THEN 'active' ELSE 'inactive' END AS status
  FROM auth.users u
  JOIN public.user_roles ur ON ur.user_id = u.id
  WHERE ur.organization_id = p_org_id

  UNION ALL

  -- Pending invitations (not yet accepted, no user_roles row)
  SELECT
    NULL::uuid      AS user_id,
    i.email         AS email,
    i.role::text    AS role,
    i.created_at_utc AS invited_at,
    NULL::timestamp with time zone AS last_sign_in,
    FALSE           AS is_active,
    'pending'       AS status
  FROM public.invitations i
  WHERE i.organization_id = p_org_id
    AND i.accepted_at_utc IS NULL
    AND i.revoked_at_utc IS NULL
    AND NOT EXISTS (
      -- Skip if this email already has a user_roles entry for this org
      SELECT 1 FROM auth.users u2
      JOIN public.user_roles ur2 ON ur2.user_id = u2.id
      WHERE u2.email = i.email
        AND ur2.organization_id = p_org_id
    )

  ORDER BY invited_at DESC;
END;
$$;

-- ── 2. Add super_admin_add_org_admin RPC ─────────────────────
--
-- Allows a SuperAdmin to add an additional admin invitation to an
-- existing organization (CT06). Delegates to the same invite logic
-- as super_admin_invite_first_admin but accepts any org (not just "first").
--
CREATE OR REPLACE FUNCTION public.super_admin_add_org_admin(
  p_org_id        uuid,
  p_email         text,
  p_invitation_id uuid,
  p_token         uuid,
  p_expires_at    timestamp with time zone,
  p_invited_by    uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
BEGIN
  -- JWT guard
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Validate organization exists
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'Organization % not found', p_org_id;
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email cannot be empty';
  END IF;

  -- Check for duplicate active invitation
  IF EXISTS (
    SELECT 1 FROM public.invitations
    WHERE organization_id = p_org_id
      AND email = lower(trim(p_email))
      AND accepted_at_utc IS NULL
      AND revoked_at_utc IS NULL
  ) THEN
    RAISE EXCEPTION 'A pending invitation already exists for % in this organization.', p_email
      USING ERRCODE = 'P0005';
  END IF;

  -- Check if user already has an active role in this org
  IF EXISTS (
    SELECT 1 FROM auth.users u
    JOIN public.user_roles ur ON ur.user_id = u.id
    WHERE u.email = lower(trim(p_email))
      AND ur.organization_id = p_org_id
      AND ur.is_active = true
  ) THEN
    RAISE EXCEPTION 'User % already has an active role in this organization.', p_email
      USING ERRCODE = 'P0006';
  END IF;

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
    p_org_id,
    lower(trim(p_email)),
    'TENANT_ADMIN',
    p_token,
    p_invited_by,
    p_expires_at
  );
END;
$$;
