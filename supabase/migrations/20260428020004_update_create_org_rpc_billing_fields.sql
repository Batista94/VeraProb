-- Extend super_admin_create_organization RPC to accept billing_day,
-- contact_email, and external_id — columns exist since 20260427010002
-- but were never wired to the RPC.
-- All new params default to NULL so existing callers are unaffected.

-- Drop all overloads to prevent ambiguity in named argument resolution
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
  -- new optional billing fields
  p_billing_day          SMALLINT     DEFAULT NULL,
  p_contact_email        TEXT         DEFAULT NULL,
  p_external_id          TEXT         DEFAULT NULL
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
  -- 1. Validate super_admin claim (only for authenticated users — service_role bypasses).
  --    (auth.jwt() ->> 'sub') IS NULL → service_role call → bypass permitted (Supabase-trusted).
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSE
    -- service_role (tests/migrations): use passed super_admin ID as actor.
    v_actor_id    := p_super_admin_user_id;
    v_actor_email := 'system@veraprob.internal';
  END IF;

  -- 2. Validate billing_day range if provided (mirrors application-layer guard)
  IF p_billing_day IS NOT NULL AND (p_billing_day < 1 OR p_billing_day > 28) THEN
    RAISE EXCEPTION 'billing_day must be between 1 and 28' USING ERRCODE = 'P0004';
  END IF;

  -- 3. Validate other inputs
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

  -- 4. Insert organization
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
    billing_day,
    contact_email,
    external_id
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
    p_billing_day,
    p_contact_email,
    p_external_id
  );

  -- 5. Record billing event (append-only — INV-3)
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
    'ORG_CREATED',
    p_plan_type,
    v_actor_id,
    p_max_vehicles,
    p_max_active_contracts,
    NOW()
  );

  -- 6. Audit log — point-in-time actor snapshot (INV-33)
  INSERT INTO public.system_audit_log (
    event_type,
    severity,
    payload,
    source,
    organization_id,
    organization_name
  )
  VALUES (
    'ORGANIZATION_CREATE',
    'info',
    jsonb_build_object(
      'actor', jsonb_build_object(
        'id',    v_actor_id,
        'email', v_actor_email,
        'role',  'super_admin'
      ),
      'action', 'ORGANIZATION_CREATE',
      'data', jsonb_build_object(
        'org_id',        v_org_id,
        'legal_name',    p_legal_name,
        'trade_name',    p_trade_name,
        'cnpj',          p_cnpj,
        'plan_type',     p_plan_type,
        'max_vehicles',  p_max_vehicles,
        'max_contracts', p_max_active_contracts,
        'billing_day',   p_billing_day,
        'contact_email', p_contact_email,
        'external_id',   p_external_id
      )
    ),
    'super_admin_rpc',
    v_org_id,
    p_trade_name
  );

  RETURN v_org_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, INT, INT, JSONB, BIGINT, INT, SMALLINT, TEXT, TEXT
) TO authenticated;
