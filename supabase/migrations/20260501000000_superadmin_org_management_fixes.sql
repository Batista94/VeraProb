-- =============================================================================
-- Tier-S: SuperAdmin Org Management Fixes
-- =============================================================================

-- 1. Update get_org_members to include is_active
DROP FUNCTION IF EXISTS public.get_org_members();

CREATE OR REPLACE FUNCTION public.get_org_members()
RETURNS TABLE (
  user_id       UUID,
  email         TEXT,
  role          TEXT,
  invited_at    TIMESTAMPTZ,
  last_sign_in  TIMESTAMPTZ,
  is_active     BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
DECLARE
  caller_org_id UUID;
BEGIN
  caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  IF caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: User does not belong to an organization';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email::text,
    ur.role::text,
    u.created_at AS invited_at,
    u.last_sign_in_at AS last_sign_in,
    ur.is_active
  FROM auth.users u
  JOIN public.user_roles ur ON ur.user_id = u.id
  WHERE ur.organization_id = caller_org_id
  ORDER BY u.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_org_members() TO authenticated;

-- 2. reactivate_member RPC
CREATE OR REPLACE FUNCTION public.reactivate_member(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
DECLARE
  v_caller_org   UUID;
  v_target_org   UUID;
BEGIN
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID;
  SELECT organization_id INTO v_target_org FROM user_roles WHERE user_id = p_target_user_id;

  IF NOT FOUND OR v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE user_roles SET is_active = true WHERE user_id = p_target_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.reactivate_member(UUID) TO authenticated;

-- 3. super_admin_unarchive_organization
CREATE OR REPLACE FUNCTION public.super_admin_unarchive_organization(
  p_org_id         UUID,
  p_reason         TEXT,
  p_super_admin_id UUID
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = p_org_id AND status = 'ARCHIVED') THEN
    RAISE EXCEPTION 'Organization not archived' USING ERRCODE = 'P0003';
  END IF;

  UPDATE organizations SET status = 'ACTIVE', updated_at = NOW() WHERE id = p_org_id;

  UPDATE user_roles SET is_active = true WHERE organization_id = p_org_id;

  UPDATE auth.users SET banned_until = NULL WHERE id IN (SELECT user_id FROM user_roles WHERE organization_id = p_org_id);

  INSERT INTO system_audit_log (event_type, severity, organization_id, reason, actor_type, source, payload)
  VALUES ('ORG_UNARCHIVED', 'info', p_org_id, p_reason, 'HUMAN', 'rpc', jsonb_build_object('super_admin_id', p_super_admin_id, 'reason', p_reason));
END;
$$;
GRANT EXECUTE ON FUNCTION public.super_admin_unarchive_organization(UUID, TEXT, UUID) TO authenticated;

-- 3a. super_admin_get_org_members
CREATE OR REPLACE FUNCTION public.super_admin_get_org_members(p_org_id UUID)
RETURNS TABLE (
  user_id       UUID,
  email         TEXT,
  role          TEXT,
  invited_at    TIMESTAMPTZ,
  last_sign_in  TIMESTAMPTZ,
  is_active     BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email::text,
    ur.role::text,
    u.created_at AS invited_at,
    u.last_sign_in_at AS last_sign_in,
    ur.is_active
  FROM auth.users u
  JOIN public.user_roles ur ON ur.user_id = u.id
  WHERE ur.organization_id = p_org_id
  ORDER BY u.created_at DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.super_admin_get_org_members(UUID) TO authenticated;

-- 3b. super_admin_toggle_member_status
CREATE OR REPLACE FUNCTION public.super_admin_toggle_member_status(
  p_org_id UUID,
  p_user_id UUID,
  p_is_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  UPDATE public.user_roles SET is_active = p_is_active WHERE organization_id = p_org_id AND user_id = p_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.super_admin_toggle_member_status(UUID, UUID, BOOLEAN) TO authenticated;

-- 4. Replace super_admin_create_organization to include organization_type

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT oid::regprocedure AS prod FROM pg_proc WHERE proname = 'super_admin_create_organization') LOOP
    EXECUTE 'DROP FUNCTION ' || r.prod;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.super_admin_create_organization(
  p_legal_name           TEXT,
  p_trade_name           TEXT,
  p_cnpj                 TEXT,
  p_timezone             TEXT,
  p_currency_code        TEXT,
  p_plan_type            TEXT,
  p_super_admin_user_id  UUID,
  p_max_vehicles         INTEGER      DEFAULT NULL,
  p_max_active_contracts INTEGER      DEFAULT NULL,
  p_capabilities         JSONB        DEFAULT NULL,
  p_tool_cost_cents      BIGINT       DEFAULT NULL,
  p_dwell_time_seconds   INTEGER      DEFAULT 300,
  p_billing_day          SMALLINT     DEFAULT NULL,
  p_contact_email        TEXT         DEFAULT NULL,
  p_external_id          TEXT         DEFAULT NULL,
  p_reason               TEXT         DEFAULT NULL,
  p_organization_type    TEXT         DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id      UUID := gen_random_uuid();
  v_actor_id    UUID := (auth.jwt() ->> 'sub')::uuid;
  v_actor_email TEXT := auth.jwt() ->> 'email';
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required' USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    v_actor_id    := p_super_admin_user_id;
    v_actor_email := 'system@veraprob.internal';
  END IF;

  IF p_billing_day IS NOT NULL AND (p_billing_day < 1 OR p_billing_day > 28) THEN
    RAISE EXCEPTION 'billing_day must be between 1 and 28' USING ERRCODE = 'P0004';
  END IF;

  IF p_legal_name IS NULL OR trim(p_legal_name) = '' THEN
    RAISE EXCEPTION 'legal_name cannot be empty';
  END IF;
  IF p_trade_name IS NULL OR trim(p_trade_name) = '' THEN
    RAISE EXCEPTION 'trade_name cannot be empty';
  END IF;
  IF p_plan_type NOT IN ('starter', 'professional', 'enterprise') THEN
    RAISE EXCEPTION 'Invalid plan_type: %. Must be starter, professional, or enterprise', p_plan_type;
  END IF;
  IF p_max_vehicles IS NOT NULL AND p_max_vehicles < 1 THEN
    RAISE EXCEPTION 'max_vehicles must be >= 1';
  END IF;
  IF p_max_active_contracts IS NOT NULL AND p_max_active_contracts < 1 THEN
    RAISE EXCEPTION 'max_active_contracts must be >= 1';
  END IF;
  IF p_tool_cost_cents IS NULL OR p_tool_cost_cents < 0 THEN
    RAISE EXCEPTION 'tool_cost_cents is required and must be >= 0' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.organizations (
    id, name, legal_name, cnpj, timezone, currency_code, plan_type,
    max_vehicles, max_active_contracts, capabilities, tool_cost_cents,
    dwell_time_seconds, billing_day, contact_email, external_id, organization_type
  )
  VALUES (
    v_org_id, p_trade_name, p_legal_name,
    CASE WHEN trim(p_cnpj) = '' THEN NULL ELSE trim(p_cnpj) END,
    p_timezone, p_currency_code, p_plan_type,
    p_max_vehicles, p_max_active_contracts,
    COALESCE(p_capabilities, '{"allows_sealing": true, "allows_loading": true, "allows_cargo_check": true, "allows_incident": true, "allows_doc": true, "smart_classify": true}'::jsonb),
    p_tool_cost_cents,
    COALESCE(p_dwell_time_seconds, 300),
    p_billing_day, p_contact_email, p_external_id, p_organization_type
  );

  INSERT INTO public.tenant_billing_events (
    organization_id, organization_name, event_type, new_plan,
    changed_by_super_admin_id, new_max_vehicles, new_max_contracts, occurred_at_utc
  )
  VALUES (
    v_org_id, p_trade_name, 'ORG_CREATED', p_plan_type,
    v_actor_id, p_max_vehicles, p_max_active_contracts, NOW()
  );

  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason
  )
  VALUES (
    'ORGANIZATION_CREATE', 'info',
    jsonb_build_object(
      'before', '{}'::jsonb,
      'after', jsonb_build_object(
        'legal_name',      p_legal_name,
        'trade_name',      p_trade_name,
        'cnpj',            p_cnpj,
        'plan_type',       p_plan_type,
        'max_vehicles',    p_max_vehicles,
        'tool_cost_cents', p_tool_cost_cents,
        'billing_day',     p_billing_day,
        'contact_email',   p_contact_email,
        'external_id',     p_external_id,
        'organization_type', p_organization_type
      )
    ),
    'super_admin_rpc', v_org_id, p_trade_name, p_reason
  );

  RETURN v_org_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization TO authenticated;

-- 5. Replace super_admin_update_organization_quota

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT oid::regprocedure AS prod FROM pg_proc WHERE proname = 'super_admin_update_organization_quota') LOOP
    EXECUTE 'DROP FUNCTION ' || r.prod;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.super_admin_update_organization_quota(
  p_org_id               UUID,
  p_new_plan_type        TEXT,
  p_new_max_vehicles     INT,
  p_new_max_contracts    INT,
  p_super_admin_user_id  UUID,
  p_reason               TEXT    DEFAULT NULL,
  p_capabilities         JSONB   DEFAULT NULL,
  p_tool_cost_cents      BIGINT  DEFAULT NULL,
  p_dwell_time_seconds   INT     DEFAULT NULL,
  p_billing_day          SMALLINT DEFAULT NULL,
  p_contact_email        TEXT    DEFAULT NULL,
  p_external_id          TEXT    DEFAULT NULL,
  p_organization_type    TEXT    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_old_plan          TEXT;
  v_old_max_vehicles  INT;
  v_old_max_contracts INT;
BEGIN
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required' USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

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
    RAISE EXCEPTION 'tool_cost_cents is required and must be >= 0' USING ERRCODE = 'P0001';
  END IF;
  
  IF p_billing_day IS NOT NULL AND (p_billing_day < 1 OR p_billing_day > 28) THEN
    RAISE EXCEPTION 'billing_day must be between 1 and 28' USING ERRCODE = 'P0004';
  END IF;

  SELECT plan_type, max_vehicles, max_active_contracts
    INTO v_old_plan, v_old_max_vehicles, v_old_max_contracts
    FROM public.organizations
   WHERE id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found.', p_org_id;
  END IF;

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
         organization_type    = p_organization_type
   WHERE id = p_org_id;

  INSERT INTO public.tenant_billing_events (
    organization_id, event_type, old_plan, new_plan,
    old_max_vehicles, new_max_vehicles, old_max_contracts, new_max_contracts,
    changed_by_super_admin_id, reason, occurred_at_utc
  )
  VALUES (
    p_org_id, 'PLAN_CHANGED', v_old_plan, p_new_plan_type,
    v_old_max_vehicles, p_new_max_vehicles, v_old_max_contracts, p_new_max_contracts,
    p_super_admin_user_id, p_reason, NOW()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.super_admin_update_organization_quota TO authenticated;

-- 6. Add organization_type to super_admin_tenant_health_view
DROP VIEW IF EXISTS public.super_admin_tenant_health_view;

CREATE VIEW public.super_admin_tenant_health_view AS
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
  COUNT(DISTINCT c.id) FILTER (WHERE c.status = 'active') AS active_contract_count,
  MAX(cf.gps_timestamp) AS last_telemetry_at,
  COUNT(DISTINCT a.id) FILTER (WHERE a.severity = 'CRITICAL' AND a.resolved_at_utc IS NULL) AS open_critical_alert_count
FROM public.organizations o
LEFT JOIN public.contracts c ON c.organization_id = o.id
LEFT JOIN public.canonical_facts cf ON cf.organization_id = o.id
LEFT JOIN public.operational_alerts a ON a.organization_id = o.id
GROUP BY o.id;
