-- =============================================================================
-- Migration: 20260917000001 — Tenant Member-Lifecycle Governance Audit
--
-- CONTEXT: Role assignment/revocation already logs to system_audit_log via
-- _rbac_audit(), but that table is only readable by Super Admin (through the
-- service-role super-admin-proxy Edge Function). Member-lifecycle mutations
-- (invite, accept, revoke invite, deactivate, reactivate, remove, legacy role
-- change) log nothing at all. Tenant Administrators/Auditors have no way to
-- see who did what to their team.
--
-- Council review (Architect + Senior Engineer + QA/Security + UX/Operations):
--   1. Reuse system_audit_log (columns already fit; _rbac_audit precedent).
--   2. Instrument the 6 currently-unlogged RPCs via _rbac_audit (enhanced to
--      auto-embed actor_id/actor_email at the DB layer — never client-side).
--   3. accept_invitation is anon-callable (no org_id in JWT yet) — audited via
--      a direct INSERT using the invitation's own organization_id.
--   4. New SECURITY DEFINER read RPC get_tenant_governance_log(), gated on the
--      EXISTING 'roles:read' permission (mirrors the Acessos tab gate exactly
--      — Administrador via '*', Validador and Auditor by default seed, never
--      Operador). Filters org_id + org_id IS NOT NULL + explicit event-type
--      allowlist (defense-in-depth against leaking system/infra rows) and
--      returns explicit typed columns, never raw JSONB.
--   5. Drop the dead system_audit_log_select_admin_policy — it checks a bare
--      `user_role` JWT claim the current custom_access_token_hook never
--      emits, so it is permanently unreachable stale security config.
--
-- CIA Triad:
--   Confidentiality — org-scoped + NOT NULL org_id + event-type allowlist +
--     least-privilege permission gate + explicit column projection (INV-1,
--     INV-2, INV-22).
--   Integrity — audit INSERT happens inside the same SECURITY DEFINER
--     transaction as the state change; remove_member captures pre-DELETE
--     state into local variables before the row disappears (INV-3).
--   Availability — existing idx_system_audit_log_org_time partial index
--     already covers (organization_id, occurred_at DESC); no new index
--     required; inserts are cheap single-row writes.
--
-- Invariants: INV-1, INV-2, INV-3, INV-10, INV-22, INV-26.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Drop dead/unreachable SELECT policy (Confidentiality — stale config) ──
-- `auth.jwt() ->> 'user_role'` is never populated by custom_access_token_hook
-- (only app_metadata.role/org_id/permissions are set). This policy has never
-- matched a single row for any client since it was written. Reads of this
-- table are and remain exclusively through SECURITY DEFINER RPCs (this
-- migration's get_tenant_governance_log for tenants, super-admin-proxy for
-- Super Admin).
DROP POLICY IF EXISTS system_audit_log_select_admin_policy ON public.system_audit_log;

-- ── 2. Enhance _rbac_audit: auto-embed actor identity at the DB layer ────────
-- Every event now carries actor_id + actor_email regardless of call site,
-- so no RPC body has to remember to pass it, and it can never be spoofed by
-- a client (derived from auth.jwt()/auth.users, not from p_payload).
CREATE OR REPLACE FUNCTION public._rbac_audit(
  p_event_type text,
  p_payload    jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_actor_id    uuid := (auth.jwt() ->> 'sub')::uuid;
  v_actor_email text;
BEGIN
  SELECT email INTO v_actor_email FROM auth.users WHERE id = v_actor_id;

  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source, organization_id, actor_type, occurred_at
  ) VALUES (
    p_event_type,
    'info',
    p_payload || jsonb_build_object('actor_id', v_actor_id, 'actor_email', v_actor_email),
    'tenant_rbac_rpc',
    public._rbac_caller_org_id(),
    'HUMAN',
    NOW()
  );
END;
$$;

-- ── 3. Instrument member-lifecycle RPCs ──────────────────────────────────────

-- deactivate_member: unchanged behavior, adds MEMBER_DEACTIVATED audit event.
CREATE OR REPLACE FUNCTION public.deactivate_member(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org   UUID;
  v_target_org   UUID;
  v_target_role  TEXT;
  v_target_email TEXT;
  v_admin_count  INT;
BEGIN
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID;

  SELECT organization_id, role, user_email INTO v_target_org, v_target_role, v_target_email
  FROM user_roles WHERE user_id = p_target_user_id AND is_active = true;

  IF NOT FOUND OR v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'P0002';
  END IF;

  IF p_target_user_id = (auth.jwt() ->> 'sub')::uuid THEN
    RAISE EXCEPTION 'Cannot deactivate yourself' USING ERRCODE = 'P0001';
  END IF;

  IF v_target_role = 'TENANT_ADMIN' THEN
    SELECT COUNT(*) INTO v_admin_count FROM user_roles
    WHERE organization_id = v_caller_org AND role = 'TENANT_ADMIN' AND is_active = true;
    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot deactivate the last administrator' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE user_roles SET is_active = false WHERE user_id = p_target_user_id;

  PERFORM public._rbac_audit(
    'MEMBER_DEACTIVATED',
    jsonb_build_object('target_user', p_target_user_id, 'target_email', v_target_email)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_member(UUID) TO authenticated;

-- reactivate_member: unchanged behavior, adds MEMBER_REACTIVATED audit event.
CREATE OR REPLACE FUNCTION public.reactivate_member(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
DECLARE
  v_caller_org   UUID;
  v_target_org   UUID;
  v_target_email TEXT;
BEGIN
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID;

  SELECT organization_id, user_email INTO v_target_org, v_target_email
  FROM user_roles WHERE user_id = p_target_user_id;

  IF NOT FOUND OR v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE user_roles SET is_active = true WHERE user_id = p_target_user_id;

  PERFORM public._rbac_audit(
    'MEMBER_REACTIVATED',
    jsonb_build_object('target_user', p_target_user_id, 'target_email', v_target_email)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reactivate_member(UUID) TO authenticated;

-- update_member_role: unchanged behavior, adds MEMBER_ROLE_CHANGED audit event.
CREATE OR REPLACE FUNCTION public.update_member_role(
  p_target_user_id UUID,
  p_new_role        TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id   UUID;
  caller_role     TEXT;
  v_target_email  TEXT;
  v_previous_role TEXT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL OR caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_new_role NOT IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR') THEN
    RAISE EXCEPTION 'Invalid role: %', p_new_role;
  END IF;

  SELECT user_email, role INTO v_target_email, v_previous_role
    FROM public.user_roles
   WHERE user_id = p_target_user_id
     AND organization_id = caller_org_id;

  UPDATE public.user_roles
  SET role = p_new_role
  WHERE user_id = p_target_user_id
    AND organization_id = caller_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found in organization';
  END IF;

  PERFORM public._rbac_audit(
    'MEMBER_ROLE_CHANGED',
    jsonb_build_object(
      'target_user', p_target_user_id,
      'target_email', v_target_email,
      'previous_role', v_previous_role,
      'new_role', p_new_role
    )
  );
END;
$$;

-- remove_member: unchanged behavior, adds MEMBER_REMOVED audit event.
-- INV-3 (Integrity): the target's email/role are captured into local
-- variables BEFORE the DELETE — the user_roles row is gone forever
-- afterward, so this is the only opportunity to record what was removed.
CREATE OR REPLACE FUNCTION public.remove_member(
  p_target_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  caller_org_id   UUID;
  caller_role     TEXT;
  admin_count     INTEGER;
  v_target_email  TEXT;
  v_previous_role TEXT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL OR caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT COUNT(*) INTO admin_count
  FROM public.user_roles
  WHERE organization_id = caller_org_id
    AND role = 'TENANT_ADMIN'
    AND user_id != p_target_user_id;

  IF admin_count = 0 THEN
    RAISE EXCEPTION 'Cannot remove the last administrator of the organization';
  END IF;

  -- Capture pre-deletion state (INV-3) before the row is permanently gone.
  SELECT user_email, role INTO v_target_email, v_previous_role
    FROM public.user_roles
   WHERE user_id = p_target_user_id
     AND organization_id = caller_org_id;

  DELETE FROM public.user_roles
  WHERE user_id = p_target_user_id
    AND organization_id = caller_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member not found in organization';
  END IF;

  PERFORM public._rbac_audit(
    'MEMBER_REMOVED',
    jsonb_build_object(
      'target_user', p_target_user_id,
      'target_email', v_target_email,
      'previous_role', v_previous_role
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_member_role(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_member(UUID) TO authenticated;

-- invite_user: unchanged behavior, adds MEMBER_INVITED audit event.
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
    (auth.jwt() ->> 'sub')::uuid,
    p_expires_at
  );

  PERFORM public._rbac_audit(
    'MEMBER_INVITED',
    jsonb_build_object('target_email', lower(trim(p_email)), 'role', p_role)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_user(TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID) TO authenticated;

-- revoke_invitation: unchanged behavior, adds INVITATION_REVOKED audit event.
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
  v_email       TEXT;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF caller_role != 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required to revoke invitations';
  END IF;

  SELECT email INTO v_email
    FROM public.invitations
   WHERE id = p_invitation_id
     AND organization_id = caller_org_id;

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

  PERFORM public._rbac_audit(
    'INVITATION_REVOKED',
    jsonb_build_object('target_email', v_email)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_invitation(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_invitation(UUID) TO authenticated;

-- accept_invitation: unchanged behavior, adds INVITATION_ACCEPTED audit event.
-- NOTE: this RPC is callable by `anon` (the accepting user may not have an
-- org_id claim in their JWT yet). _rbac_audit() cannot be reused here because
-- it derives organization_id from the CALLER's JWT via _rbac_caller_org_id(),
-- which would be NULL for this caller. Audited via a direct INSERT using the
-- invitation's own (already-validated) organization_id instead.
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
      'role', v_inv.role
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

-- ── 4. New read RPC: get_tenant_governance_log ──────────────────────────────
-- Confidentiality (INV-1, INV-2, INV-22): all three predicates are mandatory
-- — organization_id = caller's own org, organization_id IS NOT NULL, and an
-- explicit event_type allowlist. Dropping any one would leak either another
-- tenant's rows, global/system rows, or unrelated system-level event types
-- (e.g. ORGANIZATION_CREATE, ORG_UNARCHIVED) to a tenant viewer.
-- Permission gate mirrors the existing Acessos tab condition exactly
-- (settings_hub_screen.dart _canViewAccess): 'roles:read' OR 'roles:manage'
-- (both already imply '*' via has_permission()). Administrador, Validador,
-- and Auditor have 'roles:read' by default seed; Operador does not.
CREATE OR REPLACE FUNCTION public.get_tenant_governance_log(
  p_limit          int DEFAULT 50,
  p_before         timestamptz DEFAULT NULL,
  p_event_category text DEFAULT NULL,
  p_search_email   text DEFAULT NULL
)
RETURNS TABLE (
  occurred_at    timestamptz,
  event_type     text,
  actor_id       uuid,
  actor_email    text,
  target_user_id uuid,
  target_email   text,
  reason         text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id uuid;
  v_limit  int;
BEGIN
  IF NOT (public.has_permission('roles:read') OR public.has_permission('roles:manage')) THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_org_id := public._rbac_caller_org_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);

  RETURN QUERY
  SELECT
    sal.occurred_at,
    sal.event_type,
    (sal.payload ->> 'actor_id')::uuid,
    sal.payload ->> 'actor_email',
    (sal.payload ->> 'target_user')::uuid,
    sal.payload ->> 'target_email',
    sal.reason
  FROM public.system_audit_log sal
  WHERE sal.organization_id = v_org_id
    AND sal.organization_id IS NOT NULL
    AND sal.event_type = ANY(ARRAY[
      'ROLE_ASSIGNED', 'ROLE_REVOKED', 'ROLE_CHANGE_REQUESTED', 'ROLE_CHANGE_APPROVED',
      'ROLE_CHANGE_REJECTED', 'ROLE_CREATED', 'ROLE_PERMISSIONS_CHANGED',
      'MEMBER_DEACTIVATED', 'MEMBER_REACTIVATED', 'MEMBER_REMOVED', 'MEMBER_ROLE_CHANGED',
      'MEMBER_INVITED', 'INVITATION_ACCEPTED', 'INVITATION_REVOKED'
    ])
    AND (p_before IS NULL OR sal.occurred_at < p_before)
    AND (
      p_event_category IS NULL
      OR (p_event_category = 'invites' AND sal.event_type IN ('MEMBER_INVITED', 'INVITATION_ACCEPTED', 'INVITATION_REVOKED'))
      OR (p_event_category = 'roles'   AND sal.event_type LIKE 'ROLE_%')
      OR (p_event_category = 'members' AND sal.event_type IN ('MEMBER_DEACTIVATED', 'MEMBER_REACTIVATED', 'MEMBER_REMOVED', 'MEMBER_ROLE_CHANGED'))
    )
    AND (
      p_search_email IS NULL OR trim(p_search_email) = ''
      OR (sal.payload ->> 'actor_email') ILIKE '%' || trim(p_search_email) || '%'
      OR (sal.payload ->> 'target_email') ILIKE '%' || trim(p_search_email) || '%'
    )
  ORDER BY sal.occurred_at DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_tenant_governance_log(int, timestamptz, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_tenant_governance_log(int, timestamptz, text, text) TO authenticated;

RESET client_min_messages;
