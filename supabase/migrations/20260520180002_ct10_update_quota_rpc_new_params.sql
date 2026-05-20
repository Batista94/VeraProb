-- ── Migration 20260520180002 ─────────────────────────────────────────────────
-- CT10: Estende RPC super_admin_update_organization_quota com 4 novos parâmetros.
--
-- Novos parâmetros:
--   p_clock_drift_tolerance_s INT  — Motor Forense (CT10)
--   p_data_retention_days     INT  — Compliance (CT10)
--   p_connection_pool_limit   INT  — Infra (CT10)
--   p_storage_quota_gb        INT  — Infra (CT10)
--
-- Todos default NULL → DB COALESCE preserva valor existente quando não enviado.
-- Assinatura compatível com versão anterior (novos parâmetros têm DEFAULT).
-- CREATE OR REPLACE é seguro — sem drop de signature existente.
--
-- INV-3: audit log before/after inclui os 4 novos campos.
-- INV-21: diff completo para rastreabilidade forense.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (SELECT oid::regprocedure AS prod FROM pg_proc WHERE proname = 'super_admin_update_organization_quota') LOOP
    EXECUTE 'DROP FUNCTION ' || r.prod;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.super_admin_update_organization_quota(
  p_org_id                  uuid,
  p_new_plan_type           text,
  p_new_max_vehicles        int,
  p_new_max_contracts       int,
  p_super_admin_user_id     uuid,
  p_reason                  text         DEFAULT NULL,
  p_capabilities            jsonb        DEFAULT NULL,
  p_tool_cost_cents         bigint       DEFAULT NULL,
  p_dwell_time_seconds      int          DEFAULT NULL,
  p_billing_day             smallint     DEFAULT NULL,
  p_contact_email           text         DEFAULT NULL,
  p_external_id             text         DEFAULT NULL,
  p_organization_type       text         DEFAULT NULL,
  p_trade_name              text         DEFAULT NULL,
  p_legal_name              text         DEFAULT NULL,
  p_expected_updated_at     timestamptz  DEFAULT NULL,
  -- CT10 — Motor Forense, Compliance, Infraestrutura
  p_clock_drift_tolerance_s int          DEFAULT NULL,
  p_data_retention_days     int          DEFAULT NULL,
  p_connection_pool_limit   int          DEFAULT NULL,
  p_storage_quota_gb        int          DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_old_plan                 text;
  v_old_max_vehicles         int;
  v_old_max_contracts        int;
  v_old_capabilities         jsonb;
  v_old_tool_cost_cents      bigint;
  v_old_dwell_time           int;
  v_old_trade_name           text;
  v_old_legal_name           text;
  v_old_clock_drift          int;
  v_old_data_retention       int;
  v_old_pool_limit           int;
  v_old_storage_quota        int;
  v_current_updated_at       timestamptz;
  v_event_type               text;
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
  -- CT10 validations
  IF p_clock_drift_tolerance_s IS NOT NULL AND p_clock_drift_tolerance_s < 0 THEN
    RAISE EXCEPTION 'clock_drift_tolerance_s must be >= 0'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_data_retention_days IS NOT NULL AND p_data_retention_days < 1 THEN
    RAISE EXCEPTION 'data_retention_days must be >= 1'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_connection_pool_limit IS NOT NULL
     AND (p_connection_pool_limit < 1 OR p_connection_pool_limit > 500) THEN
    RAISE EXCEPTION 'connection_pool_limit must be between 1 and 500'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_storage_quota_gb IS NOT NULL AND p_storage_quota_gb < 1 THEN
    RAISE EXCEPTION 'storage_quota_gb must be >= 1'
      USING ERRCODE = 'P0001';
  END IF;

  -- Read current values for OCC check and audit diff (INV-21)
  SELECT
    plan_type, max_vehicles, max_active_contracts,
    capabilities, tool_cost_cents, dwell_time_seconds,
    name, legal_name, updated_at,
    clock_drift_tolerance_s, data_retention_days,
    connection_pool_limit, storage_quota_gb
  INTO
    v_old_plan, v_old_max_vehicles, v_old_max_contracts,
    v_old_capabilities, v_old_tool_cost_cents, v_old_dwell_time,
    v_old_trade_name, v_old_legal_name, v_current_updated_at,
    v_old_clock_drift, v_old_data_retention,
    v_old_pool_limit, v_old_storage_quota
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

  -- Determine event type based on what actually changed
  IF v_old_plan                IS NOT DISTINCT FROM p_new_plan_type
     AND v_old_max_vehicles    IS NOT DISTINCT FROM p_new_max_vehicles
     AND v_old_max_contracts   IS NOT DISTINCT FROM p_new_max_contracts
     AND v_old_tool_cost_cents IS NOT DISTINCT FROM p_tool_cost_cents THEN
    v_event_type := 'OPERATIONAL_PARAM_CHANGE';
  ELSE
    v_event_type := 'QUOTA_CHANGE';
  END IF;

  -- Update organization
  UPDATE public.organizations
     SET plan_type                = p_new_plan_type,
         max_vehicles             = p_new_max_vehicles,
         max_active_contracts     = p_new_max_contracts,
         capabilities             = COALESCE(p_capabilities, capabilities),
         tool_cost_cents          = p_tool_cost_cents,
         dwell_time_seconds       = COALESCE(p_dwell_time_seconds, dwell_time_seconds),
         billing_day              = p_billing_day,
         contact_email            = p_contact_email,
         external_id              = p_external_id,
         organization_type        = p_organization_type,
         name                     = COALESCE(NULLIF(trim(p_trade_name), ''), name),
         legal_name               = COALESCE(NULLIF(trim(p_legal_name), ''), legal_name),
         -- CT10 — novos campos (COALESCE preserva valor existente quando NULL)
         clock_drift_tolerance_s  = COALESCE(p_clock_drift_tolerance_s, clock_drift_tolerance_s),
         data_retention_days      = COALESCE(p_data_retention_days, data_retention_days),
         connection_pool_limit    = COALESCE(p_connection_pool_limit, connection_pool_limit),
         storage_quota_gb         = COALESCE(p_storage_quota_gb, storage_quota_gb)
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
  -- before/after inclui os 4 novos campos para rastreabilidade forense.
  INSERT INTO public.system_audit_log (
    event_type, severity, actor_type, payload, source,
    organization_id, organization_name, reason
  )
  VALUES (
    v_event_type,
    'info',
    'HUMAN',
    jsonb_build_object(
      'before', jsonb_build_object(
        'trade_name',              v_old_trade_name,
        'legal_name',              v_old_legal_name,
        'plan_type',               v_old_plan,
        'max_vehicles',            v_old_max_vehicles,
        'max_contracts',           v_old_max_contracts,
        'capabilities',            v_old_capabilities,
        'tool_cost_cents',         v_old_tool_cost_cents,
        'dwell_time_seconds',      v_old_dwell_time,
        'clock_drift_tolerance_s', v_old_clock_drift,
        'data_retention_days',     v_old_data_retention,
        'connection_pool_limit',   v_old_pool_limit,
        'storage_quota_gb',        v_old_storage_quota
      ),
      'after', jsonb_build_object(
        'trade_name',              COALESCE(NULLIF(trim(p_trade_name), ''), v_old_trade_name),
        'legal_name',              COALESCE(NULLIF(trim(p_legal_name), ''), v_old_legal_name),
        'plan_type',               p_new_plan_type,
        'max_vehicles',            p_new_max_vehicles,
        'max_contracts',           p_new_max_contracts,
        'capabilities',            p_capabilities,
        'tool_cost_cents',         p_tool_cost_cents,
        'dwell_time_seconds',      p_dwell_time_seconds,
        'clock_drift_tolerance_s', COALESCE(p_clock_drift_tolerance_s, v_old_clock_drift),
        'data_retention_days',     COALESCE(p_data_retention_days, v_old_data_retention),
        'connection_pool_limit',   COALESCE(p_connection_pool_limit, v_old_pool_limit),
        'storage_quota_gb',        COALESCE(p_storage_quota_gb, v_old_storage_quota)
      ),
      'super_admin_id', p_super_admin_user_id
    ),
    'super_admin_rpc',
    p_org_id,
    v_old_trade_name,
    p_reason
  );
END;
$$;

REVOKE ALL    ON FUNCTION public.super_admin_update_organization_quota FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_update_organization_quota TO authenticated;
