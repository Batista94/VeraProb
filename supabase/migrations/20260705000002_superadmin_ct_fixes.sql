-- =============================================================================
-- SuperAdmin Post-Test Fixes: CT09, CT11, CT12, CT13, CT15, CT16
-- =============================================================================
-- CT16 (CRITICAL, INV-22): Add security_invoker to tenant health view + restore
--       service_role-only grant (DROP/CREATE resets grants each migration).
-- CT09: super_admin_get_org_members returns token for pending invites;
--       add super_admin_revoke_invitation RPC (INV-3: mark revoked, no DELETE).
-- CT11: super_admin_update_organization_quota writes system_audit_log diff
--       (QUOTA_CHANGE event) on every update.
-- CT12: Archive guard in add_org_admin + toggle_member_status (P0007);
--       trigger to auto-populate denorm user_email/organization_name on
--       user_roles rows (fixes null columns from direct script inserts).
-- CT15: Optimistic concurrency control via p_expected_updated_at in quota RPC.
-- =============================================================================

-- ── 1. CT16: Recreate view with security_invoker + updated_at ─────────────────

DROP VIEW IF EXISTS public.super_admin_tenant_health_view;

CREATE VIEW public.super_admin_tenant_health_view
  WITH (security_invoker = true)
AS
SELECT
  o.id,
  o.name,
  o.legal_name,
  o.plan_type,
  o.is_active,
  o.status,
  o.max_vehicles,
  o.max_active_contracts,
  o.capabilities,
  o.tool_cost_cents,
  o.dwell_time_seconds,
  o.billing_day,
  o.contact_email,
  o.external_id,
  o.organization_type,
  o.updated_at,
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                       AS active_contract_count,
  MAX(cf.gps_timestamp)                                      AS last_telemetry_at,
  COUNT(DISTINCT a.id)
    FILTER (WHERE a.severity = 'CRITICAL' AND a.resolved_at_utc IS NULL)
                                                             AS open_critical_alert_count
FROM public.organizations o
LEFT JOIN public.contracts c
  ON c.organization_id = o.id
LEFT JOIN public.canonical_facts cf
  ON cf.organization_id = o.id
LEFT JOIN public.operational_alerts a
  ON a.organization_id = o.id
GROUP BY o.id;

-- Restore grant: DROP VIEW above erases all previous grants.
-- Only service_role (Edge Function proxy) may query the view directly.
REVOKE ALL  ON public.super_admin_tenant_health_view FROM PUBLIC;
REVOKE ALL  ON public.super_admin_tenant_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_health_view TO service_role;

-- ── 2. CT09: super_admin_get_org_members with token column ───────────────────
--
-- Drop required: PostgreSQL forbids OR REPLACE when return type changes.

DROP FUNCTION IF EXISTS public.super_admin_get_org_members(uuid);

CREATE FUNCTION public.super_admin_get_org_members(p_org_id uuid)
RETURNS TABLE(
  user_id      uuid,
  email        text,
  role         text,
  invited_at   timestamptz,
  last_sign_in timestamptz,
  is_active    boolean,
  status       text,
  token        text   -- NULL for active/inactive members; UUID token for pending invites
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Accepted members (have a user_roles row)
  RETURN QUERY
  SELECT
    u.id                                              AS user_id,
    u.email::text                                     AS email,
    ur.role::text                                     AS role,
    u.created_at                                      AS invited_at,
    u.last_sign_in_at                                 AS last_sign_in,
    ur.is_active                                      AS is_active,
    CASE WHEN ur.is_active THEN 'active'::text
         ELSE 'inactive'::text END                    AS status,
    NULL::text                                        AS token
  FROM auth.users u
  JOIN public.user_roles ur ON ur.user_id = u.id
  WHERE ur.organization_id = p_org_id

  UNION ALL

  -- Pending invitations (not yet accepted, not revoked)
  SELECT
    NULL::uuid                                        AS user_id,
    i.email                                           AS email,
    i.role::text                                      AS role,
    i.created_at_utc                                  AS invited_at,
    NULL::timestamptz                                 AS last_sign_in,
    FALSE                                             AS is_active,
    'pending'::text                                   AS status,
    i.token::text                                     AS token
  FROM public.invitations i
  WHERE i.organization_id = p_org_id
    AND i.accepted_at_utc IS NULL
    AND i.revoked_at_utc  IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM auth.users u2
      JOIN public.user_roles ur2 ON ur2.user_id = u2.id
      WHERE u2.email = i.email
        AND ur2.organization_id = p_org_id
    )

  ORDER BY invited_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_get_org_members(uuid) TO authenticated;

-- ── 3. CT09: super_admin_revoke_invitation ────────────────────────────────────
--
-- Marks the invitation revoked_at_utc (INV-3: no DELETE).

CREATE OR REPLACE FUNCTION public.super_admin_revoke_invitation(
  p_org_id         uuid,
  p_email          text,
  p_super_admin_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_invitation_id uuid;
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

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
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_revoke_invitation(uuid, text, uuid) TO authenticated;

-- ── 4. CT11 + CT15: Rebuild quota RPC with audit log + OCC + name fields ───────
--
-- Drop required: adding p_trade_name, p_legal_name, p_expected_updated_at changes
-- the function signature.

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT oid::regprocedure AS sig
      FROM pg_proc
     WHERE proname = 'super_admin_update_organization_quota'
  ) LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig;
  END LOOP;
END $$;

CREATE FUNCTION public.super_admin_update_organization_quota(
  p_org_id              uuid,
  p_new_plan_type       text,
  p_new_max_vehicles    int,
  p_new_max_contracts   int,
  p_super_admin_user_id uuid,
  p_reason              text         DEFAULT NULL,
  p_capabilities        jsonb        DEFAULT NULL,
  p_tool_cost_cents     bigint       DEFAULT NULL,
  p_dwell_time_seconds  int          DEFAULT NULL,
  p_billing_day         smallint     DEFAULT NULL,
  p_contact_email       text         DEFAULT NULL,
  p_external_id         text         DEFAULT NULL,
  p_organization_type   text         DEFAULT NULL,
  -- CT10: editable name fields
  p_trade_name          text         DEFAULT NULL,
  p_legal_name          text         DEFAULT NULL,
  -- CT15: optimistic concurrency — pass the updated_at you loaded; NULL skips check
  p_expected_updated_at timestamptz  DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_old_plan            text;
  v_old_max_vehicles    int;
  v_old_max_contracts   int;
  v_old_capabilities    jsonb;
  v_old_tool_cost_cents bigint;
  v_old_dwell_time      int;
  v_org_name            text;
  v_current_updated_at  timestamptz;
BEGIN
  -- JWT guard
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Input validation
  IF p_new_plan_type NOT IN ('starter', 'professional', 'enterprise') THEN
    RAISE EXCEPTION 'Invalid plan_type: %. Must be starter, professional, or enterprise.', p_new_plan_type;
  END IF;
  IF p_new_max_vehicles IS NOT NULL AND p_new_max_vehicles < 1 THEN
    RAISE EXCEPTION 'max_vehicles must be >= 1 (or NULL for unlimited).';
  END IF;
  IF p_new_max_contracts IS NOT NULL AND p_new_max_contracts < 1 THEN
    RAISE EXCEPTION 'max_active_contracts must be >= 1 (or NULL for unlimited).';
  END IF;
  IF p_tool_cost_cents IS NULL OR p_tool_cost_cents < 0 THEN
    RAISE EXCEPTION 'tool_cost_cents is required and must be >= 0'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_billing_day IS NOT NULL AND (p_billing_day < 1 OR p_billing_day > 28) THEN
    RAISE EXCEPTION 'billing_day must be between 1 and 28'
      USING ERRCODE = 'P0004';
  END IF;

  -- Read current values for OCC check and audit diff
  SELECT
    plan_type, max_vehicles, max_active_contracts,
    capabilities, tool_cost_cents, dwell_time_seconds,
    name, updated_at
  INTO
    v_old_plan, v_old_max_vehicles, v_old_max_contracts,
    v_old_capabilities, v_old_tool_cost_cents, v_old_dwell_time,
    v_org_name, v_current_updated_at
  FROM public.organizations
  WHERE id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found.', p_org_id;
  END IF;

  -- CT15: Optimistic Concurrency Control
  IF p_expected_updated_at IS NOT NULL
     AND v_current_updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'Stale data: organization was modified since you loaded it. Please refresh and retry.'
      USING ERRCODE = '40001';
  END IF;

  -- Update organization
  UPDATE public.organizations
     SET plan_type            = p_new_plan_type,
         max_vehicles         = p_new_max_vehicles,
         max_active_contracts = p_new_max_contracts,
         capabilities         = COALESCE(p_capabilities, capabilities),
         tool_cost_cents      = p_tool_cost_cents,
         dwell_time_seconds   = COALESCE(p_dwell_time_seconds, dwell_time_seconds),
         billing_day          = p_billing_day,
         contact_email        = p_contact_email,
         external_id          = p_external_id,
         organization_type    = p_organization_type,
         name                 = COALESCE(NULLIF(trim(p_trade_name), ''), name),
         legal_name           = COALESCE(NULLIF(trim(p_legal_name), ''), legal_name)
   WHERE id = p_org_id;

  -- Append immutable billing event (INV-3)
  INSERT INTO public.tenant_billing_events (
    organization_id,
    event_type,
    old_plan,
    new_plan,
    old_max_vehicles,
    new_max_vehicles,
    old_max_contracts,
    new_max_contracts,
    changed_by_super_admin_id,
    reason,
    occurred_at_utc
  )
  VALUES (
    p_org_id,
    'PLAN_CHANGED',
    v_old_plan,
    p_new_plan_type,
    v_old_max_vehicles,
    p_new_max_vehicles,
    v_old_max_contracts,
    p_new_max_contracts,
    p_super_admin_user_id,
    p_reason,
    NOW()
  );

  -- CT11: Append audit log diff (INV-3, INV-21)
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason
  )
  VALUES (
    'QUOTA_CHANGE',
    'info',
    jsonb_build_object(
      'before', jsonb_build_object(
        'plan_type',       v_old_plan,
        'max_vehicles',    v_old_max_vehicles,
        'max_contracts',   v_old_max_contracts,
        'capabilities',    v_old_capabilities,
        'tool_cost_cents', v_old_tool_cost_cents,
        'dwell_time_seconds', v_old_dwell_time
      ),
      'after', jsonb_build_object(
        'plan_type',       p_new_plan_type,
        'max_vehicles',    p_new_max_vehicles,
        'max_contracts',   p_new_max_contracts,
        'capabilities',    p_capabilities,
        'tool_cost_cents', p_tool_cost_cents,
        'dwell_time_seconds', p_dwell_time_seconds
      ),
      'super_admin_id', p_super_admin_user_id
    ),
    'super_admin_rpc',
    p_org_id,
    v_org_name,
    p_reason
  );
END;
$$;

REVOKE ALL   ON FUNCTION public.super_admin_update_organization_quota FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_update_organization_quota TO authenticated;

-- ── 5. CT12: Archive guard in super_admin_add_org_admin ──────────────────────

CREATE OR REPLACE FUNCTION public.super_admin_add_org_admin(
  p_org_id        uuid,
  p_email         text,
  p_invitation_id uuid,
  p_token         uuid,
  p_expires_at    timestamptz,
  p_invited_by    uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_org_status text;
BEGIN
  -- JWT guard
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Validate organization exists and is not archived (CT12)
  SELECT status INTO v_org_status
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
END;
$$;

-- ── 6. CT12: Archive guard in super_admin_toggle_member_status ───────────────

CREATE OR REPLACE FUNCTION public.super_admin_toggle_member_status(
  p_org_id    uuid,
  p_user_id   uuid,
  p_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_org_status text;
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  SELECT status INTO v_org_status
  FROM public.organizations
  WHERE id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found', p_org_id;
  END IF;

  -- CT12: block member status changes on archived orgs
  IF v_org_status = 'ARCHIVED' THEN
    RAISE EXCEPTION 'Cannot modify member status for an archived organization.'
      USING ERRCODE = 'P0007';
  END IF;

  UPDATE public.user_roles
     SET is_active = p_is_active
   WHERE organization_id = p_org_id
     AND user_id          = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_toggle_member_status(uuid, uuid, boolean) TO authenticated;

-- ── 7. CT12: Trigger to auto-populate denorm columns on user_roles ────────────
--
-- Fixes null user_email / organization_name when rows are inserted via direct
-- SQL scripts that bypass the accept_invitation RPC.

CREATE OR REPLACE FUNCTION public.fn_user_roles_populate_denorm()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
BEGIN
  IF NEW.user_email IS NULL OR NEW.user_email = '' THEN
    SELECT email INTO NEW.user_email
      FROM auth.users
     WHERE id = NEW.user_id;
  END IF;

  IF NEW.organization_name IS NULL OR NEW.organization_name = '' THEN
    SELECT name INTO NEW.organization_name
      FROM public.organizations
     WHERE id = NEW.organization_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_roles_denorm ON public.user_roles;
CREATE TRIGGER trg_user_roles_denorm
  BEFORE INSERT OR UPDATE ON public.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_user_roles_populate_denorm();

-- Backfill existing rows that have null denorm columns
UPDATE public.user_roles ur
   SET user_email        = COALESCE(ur.user_email,        u.email),
       organization_name = COALESCE(ur.organization_name, o.name)
  FROM auth.users u,
       public.organizations o
 WHERE ur.user_id         = u.id
   AND o.id               = ur.organization_id
   AND (ur.user_email IS NULL OR ur.organization_name IS NULL);
