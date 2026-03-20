-- =============================================================================
-- Phase 9.2 — SuperAdmin RPCs (SECURITY DEFINER)
-- =============================================================================
-- D4: SuperAdmin RPCs bypass TENANT_ADMIN JWT check — they validate super_admin claim.
-- Both RPCs are SECURITY DEFINER and run with elevated privileges.
-- Neither RPC is accessible via anon client — GRANT only to authenticated.
-- =============================================================================


-- =============================================================================
-- RPC 1: super_admin_create_organization
-- =============================================================================
-- Atomically creates an organization + initial billing event.
-- Validates super_admin: true in JWT before any mutation.
-- Returns the new organization UUID.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_create_organization(
  p_legal_name            TEXT,
  p_trade_name            TEXT,
  p_cnpj                  TEXT,
  p_timezone              TEXT,
  p_currency_code         TEXT,
  p_plan_type             TEXT,
  p_max_vehicles          INT,
  p_max_active_contracts  INT,
  p_super_admin_user_id   UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_is_super  TEXT;
  v_org_id    UUID := gen_random_uuid();
BEGIN
  -- 1. Validate super_admin claim
  v_is_super := auth.jwt() -> 'app_metadata' ->> 'super_admin';
  IF v_is_super IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Unauthorized: super_admin claim required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Validate inputs
  IF p_legal_name IS NULL OR trim(p_legal_name) = '' THEN
    RAISE EXCEPTION 'legal_name cannot be empty';
  END IF;
  IF p_trade_name IS NULL OR trim(p_trade_name) = '' THEN
    RAISE EXCEPTION 'trade_name cannot be empty';
  END IF;
  IF p_plan_type NOT IN ('starter', 'professional', 'enterprise') THEN
    RAISE EXCEPTION 'Invalid plan_type: %. Must be starter, professional, or enterprise', p_plan_type;
  END IF;
  IF p_max_vehicles < 1 THEN
    RAISE EXCEPTION 'max_vehicles must be >= 1';
  END IF;
  IF p_max_active_contracts < 1 THEN
    RAISE EXCEPTION 'max_active_contracts must be >= 1';
  END IF;

  -- 3. Insert organization
  INSERT INTO public.organizations (
    id,
    name,
    legal_name,
    cnpj,
    timezone,
    currency_code,
    plan_type,
    max_vehicles,
    max_active_contracts,
    is_active
  )
  VALUES (
    v_org_id,
    p_trade_name,
    p_legal_name,
    CASE WHEN trim(p_cnpj) = '' THEN NULL ELSE trim(p_cnpj) END,
    p_timezone,
    p_currency_code,
    p_plan_type,
    p_max_vehicles,
    p_max_active_contracts,
    true
  );

  -- 4. Record billing event (append-only — triggers block UPDATE/DELETE)
  INSERT INTO public.tenant_billing_events (
    organization_id,
    event_type,
    new_plan,
    changed_by_super_admin_id,
    new_max_vehicles,
    new_max_contracts,
    occurred_at_utc
  )
  VALUES (
    v_org_id,
    'ORG_CREATED',
    p_plan_type,
    p_super_admin_user_id,
    p_max_vehicles,
    p_max_active_contracts,
    NOW()
  );

  RETURN v_org_id;
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID
) TO authenticated;


-- =============================================================================
-- RPC 2: super_admin_invite_first_admin
-- =============================================================================
-- Inserts an invitation for a new org's first admin.
-- Bypasses invite_user (which requires TENANT_ADMIN JWT — SuperAdmin has none).
-- Accepts p_org_id explicitly instead of reading from JWT.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_invite_first_admin(
  p_org_id        UUID,
  p_email         TEXT,
  p_role          TEXT,
  p_token         TEXT,
  p_invitation_id UUID,
  p_expires_at    TIMESTAMPTZ,
  p_invited_by    UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_is_super TEXT;
BEGIN
  -- 1. Validate super_admin claim
  v_is_super := auth.jwt() -> 'app_metadata' ->> 'super_admin';
  IF v_is_super IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Unauthorized: super_admin claim required'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- 2. Validate org exists
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'Organization % not found', p_org_id;
  END IF;

  -- 3. Validate role
  IF p_role NOT IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be TENANT_ADMIN, OPERATOR, or AUDITOR', p_role;
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email cannot be empty';
  END IF;

  -- 4. Revoke any existing pending invite for this email in this org
  UPDATE public.invitations
  SET revoked_at_utc = now()
  WHERE organization_id = p_org_id
    AND email           = lower(trim(p_email))
    AND accepted_at_utc IS NULL
    AND revoked_at_utc  IS NULL;

  -- 5. Insert new invitation
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
    p_role,
    p_token,
    p_invited_by,
    p_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_invite_first_admin(
  UUID, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, UUID
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_invite_first_admin(
  UUID, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, UUID
) TO authenticated;
