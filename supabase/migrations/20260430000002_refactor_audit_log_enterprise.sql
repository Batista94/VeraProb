-- Phase 9 — Enterprise Audit Log Refactor (Point-in-Time Identity)
-- Refactors ORGANIZATION_CREATE payload to include full actor snapshot.
-- Implements "Big Tech Identity Standard" (INV-33).

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
  v_is_super      TEXT;
  v_org_id        UUID := gen_random_uuid();
  v_actor_id      UUID := (auth.jwt() ->> 'sub')::uuid;
  v_actor_email   TEXT := auth.jwt() ->> 'email';
  v_actor_role    TEXT := 'super_admin'; -- Default for this RPC
BEGIN
  -- 1. Validate super_admin claim
  -- Service-role connections (migrations, Edge Functions) have (auth.jwt() ->> 'sub') = NULL;
  -- skip the claim check so integration tests using the service key work correctly.
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    v_is_super := auth.jwt() -> 'app_metadata' ->> 'super_admin';
    IF v_is_super IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    -- For service_role (tests/migrations), fallback or use passed ID
    v_actor_id := p_super_admin_user_id;
    v_actor_email := 'system@veraprob.internal'; 
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
    status
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
    'ACTIVE'
  );

  -- 4. Record billing event (append-only — triggers block UPDATE/DELETE)
  INSERT INTO public.tenant_billing_events (
    organization_id,
    organization_name,
    event_type,
    new_plan,
    changed_by_super_admin_id,
    new_max_vehicles,
    new_max_contracts,
    occurred_at_utc
  )
  VALUES (
    v_org_id,
    p_trade_name,
    'ORG_CREATED', -- Billing system still uses old event names for continuity
    p_plan_type,
    v_actor_id,
    p_max_vehicles,
    p_max_active_contracts,
    NOW()
  );

  -- 5. Emit audit log entry (Enterprise Point-in-Time Identity)
  -- Implements "Big Tech Identity Standard" (INV-33): snapshot actor info
  INSERT INTO public.system_audit_log (
    event_type,
    severity,
    payload,
    source,
    organization_id,
    organization_name
  )
  VALUES (
    'ORGANIZATION_CREATE', -- Action name updated per requirement
    'info',
    jsonb_build_object(
      'actor', jsonb_build_object(
         'id',    v_actor_id,
         'email', v_actor_email,
         'role',  v_actor_role
      ),
      'action', 'ORGANIZATION_CREATE',
      'data', jsonb_build_object(
        'org_id',         v_org_id,
        'legal_name',     p_legal_name,
        'trade_name',     p_trade_name,
        'cnpj',           p_cnpj,
        'plan_type',      p_plan_type,
        'max_vehicles',   p_max_vehicles,
        'max_contracts',  p_max_active_contracts
      )
    ),
    'super_admin_rpc',
    v_org_id,
    p_trade_name
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

