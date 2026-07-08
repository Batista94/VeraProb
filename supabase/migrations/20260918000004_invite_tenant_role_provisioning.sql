-- =============================================================================
-- Migration: 20260918000004_invite_tenant_role_provisioning.sql
-- Bug 3 and Bug 4: Direct provisioning of profiles from invites and preventing
-- privilege escalation (users:manage cannot grant TENANT_ADMIN).
-- =============================================================================

-- Add the fine-grained role ID to the invitation
ALTER TABLE public.invitations ADD COLUMN IF NOT EXISTS tenant_role_id UUID REFERENCES public.tenant_roles(id);

-- Helper to detect System Admin profiles
CREATE OR REPLACE FUNCTION public._is_admin_profile(p_tenant_role_id UUID) RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenant_roles
    WHERE id = p_tenant_role_id
      AND is_system = true
      AND name = 'Administrador'
  );
$$;

GRANT EXECUTE ON FUNCTION public._is_admin_profile(UUID) TO authenticated, service_role;

-- ── 1. RPC: invite_user (6 params overloaded signature) ──────────────────────
CREATE OR REPLACE FUNCTION public.invite_user(
  p_email         TEXT,
  p_role          TEXT,
  p_token         TEXT,
  p_expires_at    TIMESTAMPTZ,
  p_invitation_id UUID,
  p_tenant_role_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
  caller_role   TEXT;
  caller_perms  jsonb;
  target_is_admin BOOLEAN := false;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';
  caller_perms  := auth.jwt() -> 'app_metadata' -> 'permissions';

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  -- 1. Base gating: must be TENANT_ADMIN OR have users:manage
  IF caller_role != 'TENANT_ADMIN' AND NOT (caller_perms ? 'users:manage') THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN or users:manage permission required to invite users';
  END IF;

  -- 2. Privilege Escalation Prevention
  IF p_role = 'TENANT_ADMIN' THEN
    target_is_admin := true;
  ELSIF p_tenant_role_id IS NOT NULL THEN
    target_is_admin := public._is_admin_profile(p_tenant_role_id);
  END IF;

  IF target_is_admin AND caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: Only a TENANT_ADMIN can invite another Admin';
  END IF;

  IF p_tenant_role_id IS NOT NULL THEN
    -- Verify role belongs to caller org and is not deleted
    IF NOT EXISTS (
      SELECT 1 FROM public.tenant_roles 
      WHERE id = p_tenant_role_id 
        AND organization_id = caller_org_id 
        AND deleted_at IS NULL
    ) THEN
      RAISE EXCEPTION 'P0002: Tenant role not found or belongs to another organization';
    END IF;
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
    tenant_role_id,
    token,
    invited_by,
    expires_at_utc
  )
  VALUES (
    p_invitation_id,
    caller_org_id,
    lower(trim(p_email)),
    p_role,
    p_tenant_role_id,
    p_token,
    (auth.jwt() ->> 'sub')::uuid,
    p_expires_at
  );

  PERFORM public._rbac_audit(
    'MEMBER_INVITED',
    jsonb_build_object('target_email', lower(trim(p_email)), 'role', p_role, 'tenant_role_id', p_tenant_role_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, UUID) TO authenticated;

-- ── 2. RPC: invite_user (5 params original proxy) ────────────────────────────
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
BEGIN
  -- Proxy to the new 6-param version
  PERFORM public.invite_user(p_email, p_role, p_token, p_expires_at, p_invitation_id, NULL::UUID);
END;
$$;

REVOKE ALL ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) TO authenticated;

-- ── 3. RPC: accept_invitation (Provisionamento Direto) ───────────────────────
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

  IF v_email IS DISTINCT FROM v_inv.email THEN
    RAISE EXCEPTION 'User email does not match invitation recipient';
  END IF;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = v_inv.organization_id;

  SELECT organization_id INTO v_existing_org
  FROM public.user_roles
  WHERE user_id = p_user_id;

  IF FOUND AND v_existing_org IS DISTINCT FROM v_inv.organization_id THEN
    RAISE EXCEPTION
      'User is already a member of a different organization. '
      'Org transfer requires explicit admin authorization.';
  END IF;

  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
      updated_at         = now()
  WHERE id    = p_user_id
    AND email = v_inv.email;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'User email mismatch at auth.users update — TOCTOU guard triggered, aborting';
  END IF;

  UPDATE public.invitations
  SET accepted_at_utc = now()
  WHERE id = v_inv.id;

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

  -- ── Provisionamento Direto de Perfil Customizado (Bug 4) ──
  IF v_inv.tenant_role_id IS NOT NULL THEN
    INSERT INTO public.user_tenant_roles (
      user_id, 
      tenant_role_id, 
      organization_id, 
      granted_by, 
      valid_from, 
      revoked_at
    )
    VALUES (
      p_user_id, 
      v_inv.tenant_role_id, 
      v_inv.organization_id, 
      v_inv.invited_by, 
      now(), 
      NULL
    )
    ON CONFLICT (user_id, tenant_role_id) DO UPDATE 
    SET revoked_at = NULL, valid_from = now();

    -- If the profile granted is System Admin, promote coarse role just in case
    IF public._is_admin_profile(v_inv.tenant_role_id) THEN
      PERFORM public._rbac_sync_coarse_role_admin(p_user_id, v_inv.organization_id);
    END IF;
  END IF;

  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source, organization_id, actor_type, occurred_at
  ) VALUES (
    'INVITATION_ACCEPTED',
    'info',
    jsonb_build_object(
      'actor_id', p_user_id,
      'actor_email', v_email,
      'target_user', p_user_id,
      'target_email', v_email,
      'role', v_inv.role,
      'tenant_role_id', v_inv.tenant_role_id
    ),
    'tenant_rbac_rpc',
    v_inv.organization_id,
    'HUMAN',
    NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_invitation(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_invitation(TEXT, UUID) TO anon, authenticated;
