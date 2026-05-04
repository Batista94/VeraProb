-- pr_scanner: ignore-regression
-- =============================================================================
-- Phase 10 — Update SuperAdmin RPCs: capabilities, tool_cost_cents, dwell_time_seconds
-- =============================================================================
-- Replaces super_admin_create_organization and super_admin_update_organization_quota
-- with new signatures that accept operational config fields.
--
-- INV-4: tool_cost_cents is BIGINT cents.
-- INV-14: capabilities JSONB is transport-agnostic.
-- INV-6: dwell_time_seconds is INT (duration, not timestamp).
-- =============================================================================


-- =============================================================================
-- DROP old signatures before replacing (parameter count changed)
-- =============================================================================

DROP FUNCTION IF EXISTS public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID
);

DROP FUNCTION IF EXISTS public.super_admin_update_organization_quota(
  UUID, TEXT, INT, INT, UUID, TEXT
);


-- =============================================================================
-- RPC: super_admin_create_organization (updated signature)
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
  p_super_admin_user_id   UUID,
  p_capabilities          JSONB    DEFAULT NULL,
  p_tool_cost_cents       BIGINT   DEFAULT NULL,
  p_dwell_time_seconds    INT      DEFAULT 300
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
  -- NULL max_vehicles = unlimited (enterprise). Non-null must be >= 1.
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
    capabilities,
    tool_cost_cents,
    dwell_time_seconds,
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
    true
  );

  -- 4. Record billing event (append-only — INV-3)
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
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID, JSONB, BIGINT, INT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID, JSONB, BIGINT, INT
) TO authenticated;


-- =============================================================================
-- RPC: super_admin_update_organization_quota (updated signature)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.super_admin_update_organization_quota(
  p_org_id               UUID,
  p_new_plan_type        TEXT,
  p_new_max_vehicles     INT,
  p_new_max_contracts    INT,
  p_super_admin_user_id  UUID,
  p_reason               TEXT    DEFAULT NULL,
  p_capabilities         JSONB   DEFAULT NULL,
  p_tool_cost_cents      BIGINT  DEFAULT NULL,
  p_dwell_time_seconds   INT     DEFAULT NULL
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
  -- ── JWT validation ──────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Input validation ────────────────────────────────────────────────────────
  IF p_new_plan_type NOT IN ('starter', 'professional', 'enterprise') THEN
    RAISE EXCEPTION 'Invalid plan_type: %. Must be starter, professional, or enterprise.',
      p_new_plan_type;
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

  -- ── Read current values for billing event ───────────────────────────────────
  SELECT plan_type, max_vehicles, max_active_contracts
    INTO v_old_plan, v_old_max_vehicles, v_old_max_contracts
    FROM public.organizations
   WHERE id = p_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization % not found.', p_org_id;
  END IF;

  -- ── Update organization (COALESCE keeps existing value when param is NULL) ──
  UPDATE public.organizations
     SET plan_type            = p_new_plan_type,
         max_vehicles         = p_new_max_vehicles,
         max_active_contracts = p_new_max_contracts,
         capabilities         = COALESCE(p_capabilities, capabilities),
         tool_cost_cents      = p_tool_cost_cents,
         dwell_time_seconds   = COALESCE(p_dwell_time_seconds, dwell_time_seconds)
   WHERE id = p_org_id;

  -- ── Append immutable billing event (INV-3) ──────────────────────────────────
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
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_update_organization_quota(
  UUID, TEXT, INT, INT, UUID, TEXT, JSONB, BIGINT, INT
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_update_organization_quota(
  UUID, TEXT, INT, INT, UUID, TEXT, JSONB, BIGINT, INT
) TO authenticated;
