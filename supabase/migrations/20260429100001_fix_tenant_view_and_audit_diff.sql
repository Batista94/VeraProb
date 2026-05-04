-- pr_scanner: ignore-regression
-- =============================================================================
-- Fix: Tenant Health View missing fields + Audit Diff payload + Governance
-- =============================================================================
-- A. View: add capabilities, tool_cost_cents, dwell_time_seconds,
--          billing_day, contact_email, external_id.
-- B. RPC:  add p_reason param, rebuild audit payload as Diff format.
-- C. Governance trigger: enforce reason NOT NULL for ORGANIZATION_CREATE.
--
-- INV-3: NO DROP of immutability rules. All operations are DDL-only.
-- =============================================================================

-- ── A. Recreate view with missing columns ────────────────────────────────────

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
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                     AS active_contract_count,
  MAX(cf.gps_timestamp)                                    AS last_telemetry_at,
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

-- ── B. Recreate RPC with p_reason + Diff payload ────────────────────────────

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
  p_reason               TEXT         DEFAULT NULL
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
  -- 1. Validate super_admin claim
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    v_actor_id    := p_super_admin_user_id;
    v_actor_email := 'system@veraprob.internal';
  END IF;

  -- 2. Validate billing_day range
  IF p_billing_day IS NOT NULL AND (p_billing_day < 1 OR p_billing_day > 28) THEN
    RAISE EXCEPTION 'billing_day must be between 1 and 28' USING ERRCODE = 'P0004';
  END IF;

  -- 3. Validate inputs
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
    RAISE EXCEPTION 'tool_cost_cents is required and must be >= 0'
      USING ERRCODE = 'P0001';
  END IF;

  -- 4. Insert organization
  INSERT INTO public.organizations (
    id, name, legal_name, cnpj, timezone, currency_code, plan_type,
    max_vehicles, max_active_contracts, capabilities, tool_cost_cents,
    dwell_time_seconds, billing_day, contact_email, external_id
  )
  VALUES (
    v_org_id, p_trade_name, p_legal_name,
    CASE WHEN trim(p_cnpj) = '' THEN NULL ELSE trim(p_cnpj) END,
    p_timezone, p_currency_code, p_plan_type,
    p_max_vehicles, p_max_active_contracts,
    COALESCE(p_capabilities, '{
      "allows_sealing": true,
      "allows_loading": true,
      "allows_cargo_check": true,
      "allows_incident": true,
      "allows_doc": true,
      "smart_classify": true
    }'::jsonb),
    p_tool_cost_cents,
    COALESCE(p_dwell_time_seconds, 300),
    p_billing_day, p_contact_email, p_external_id
  );

  -- 5. Billing event (INV-3)
  INSERT INTO public.tenant_billing_events (
    organization_id, organization_name, event_type, new_plan,
    changed_by_super_admin_id, new_max_vehicles, new_max_contracts,
    occurred_at_utc
  )
  VALUES (
    v_org_id, p_trade_name, 'ORG_CREATED', p_plan_type,
    v_actor_id, p_max_vehicles, p_max_active_contracts, NOW()
  );

  -- 6. Audit log — Diff format (INV-3)
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
        'external_id',     p_external_id
      )
    ),
    'super_admin_rpc', v_org_id, p_trade_name, p_reason
  );

  RETURN v_org_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, INT, INT, JSONB, BIGINT, INT, SMALLINT, TEXT, TEXT, TEXT
) TO authenticated;

-- ── C. Governance trigger: add ORGANIZATION_CREATE to reason-required list ───

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
    'ORGANIZATION_CREATE'
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
