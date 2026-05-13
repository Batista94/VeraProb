-- =============================================================================
-- Admin Management Audit Logging
-- =============================================================================
-- Adds systemic audit logging for admin privilege mutations:
--   ADMIN_INVITE, ADMIN_REVOKE, ADMIN_RESEND_INVITE
--
-- INV-3:  Append-only audit trail for all privilege changes.
-- INV-10: Mandatory reason enforced by governance trigger.
-- =============================================================================

-- ── 1. Update governance trigger to include new event types ──────────────────

CREATE OR REPLACE FUNCTION public.system_audit_log_governance_check()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.event_type IN (
    'QUOTA_CHANGE',
    'STATUS_CHANGE',
    'LIMIT_CHANGE',
    'SECRET_ROTATION',
    'IMPERSONATION_START',
    'IMPERSONATION_REVOKE',
    'OPERATIONAL_PARAM_CHANGE',
    'ADMIN_INVITE',
    'ADMIN_REVOKE',
    'ADMIN_RESEND_INVITE'
  ) THEN
    IF NEW.reason IS NULL OR trim(NEW.reason) = '' THEN
      RAISE EXCEPTION 'Governance event "%" requires a non-empty reason', NEW.event_type
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.actor_type = 'IMPERSONATOR' AND NEW.impersonator_id IS NULL THEN
    RAISE EXCEPTION 'actor_type IMPERSONATOR requires impersonator_id'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2. Update super_admin_add_org_admin with p_reason + audit log ────────────

CREATE OR REPLACE FUNCTION public.super_admin_add_org_admin(
  p_org_id        uuid,
  p_email         text,
  p_invitation_id uuid,
  p_token         uuid,
  p_expires_at    timestamptz,
  p_invited_by    uuid,
  p_reason        text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_org_status text;
  v_org_name   text;
BEGIN
  -- JWT guard
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Validate organization exists and is not archived (CT12)
  SELECT status, name INTO v_org_status, v_org_name
  FROM public.organizations
  WHERE id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found', p_org_id;
  END IF;

  IF v_org_status NOT IN ('ACTIVE', 'TRIAL') THEN
    RAISE EXCEPTION 'Cannot add admin to organization with status %. Only ACTIVE or TRIAL organizations accept new admins.', v_org_status
      USING ERRCODE = 'P0007';
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email cannot be empty';
  END IF;

  -- Duplicate active invitation
  IF EXISTS (
    SELECT 1 FROM public.invitations
    WHERE organization_id = p_org_id
      AND email           = lower(trim(p_email))
      AND accepted_at_utc IS NULL
      AND revoked_at_utc  IS NULL
  ) THEN
    RAISE EXCEPTION 'A pending invitation already exists for % in this organization.', p_email
      USING ERRCODE = 'P0005';
  END IF;

  -- User already active in org
  IF EXISTS (
    SELECT 1 FROM auth.users u
    JOIN public.user_roles ur ON ur.user_id = u.id
    WHERE u.email             = lower(trim(p_email))
      AND ur.organization_id  = p_org_id
      AND ur.is_active        = true
  ) THEN
    RAISE EXCEPTION 'User % already has an active role in this organization.', p_email
      USING ERRCODE = 'P0006';
  END IF;

  INSERT INTO public.invitations (
    id, organization_id, email, role, token, invited_by, expires_at_utc
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

  -- Audit log (INV-3, INV-10)
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason, actor_type
  )
  VALUES (
    'ADMIN_INVITE',
    'info',
    jsonb_build_object(
      'email', lower(trim(p_email)),
      'organization_id', p_org_id,
      'actor_id', p_invited_by,
      'invitation_id', p_invitation_id
    ),
    'super_admin_rpc',
    p_org_id,
    v_org_name,
    p_reason,
    'HUMAN'
  );
END;
$$;

-- ── 3. Update super_admin_revoke_invitation with p_reason + audit log ────────

DROP FUNCTION IF EXISTS public.super_admin_revoke_invitation(uuid, text, uuid);

CREATE FUNCTION public.super_admin_revoke_invitation(
  p_org_id         uuid,
  p_email          text,
  p_super_admin_id uuid,
  p_reason         text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_invitation_id uuid;
  v_org_name      text;
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = p_org_id;

  SELECT id INTO v_invitation_id
  FROM public.invitations
  WHERE organization_id = p_org_id
    AND email           = lower(trim(p_email))
    AND accepted_at_utc IS NULL
    AND revoked_at_utc  IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No pending invitation found for % in this organization.', p_email
      USING ERRCODE = 'P0008';
  END IF;

  -- INV-3: never DELETE — set revoked timestamp instead
  UPDATE public.invitations
     SET revoked_at_utc = NOW()
   WHERE id = v_invitation_id;

  -- Audit log (INV-3, INV-10)
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason, actor_type
  )
  VALUES (
    'ADMIN_REVOKE',
    'warning',
    jsonb_build_object(
      'email', lower(trim(p_email)),
      'organization_id', p_org_id,
      'actor_id', p_super_admin_id,
      'invitation_id', v_invitation_id
    ),
    'super_admin_rpc',
    p_org_id,
    v_org_name,
    p_reason,
    'HUMAN'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_revoke_invitation(uuid, text, uuid, text) TO authenticated;

-- ── 4. Create super_admin_audit_resend_invitation ────────────────────────────

CREATE FUNCTION public.super_admin_audit_resend_invitation(
  p_org_id  uuid,
  p_email   text,
  p_reason  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_org_name text;
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT name INTO v_org_name
  FROM public.organizations
  WHERE id = p_org_id;

  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason, actor_type
  )
  VALUES (
    'ADMIN_RESEND_INVITE',
    'info',
    jsonb_build_object(
      'email', lower(trim(p_email)),
      'organization_id', p_org_id,
      'actor_id', (auth.jwt() ->> 'sub')::uuid
    ),
    'super_admin_rpc',
    p_org_id,
    v_org_name,
    p_reason,
    'HUMAN'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_audit_resend_invitation(uuid, text, text) TO authenticated;
