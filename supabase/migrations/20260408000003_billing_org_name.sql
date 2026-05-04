--
-- =============================================================================
-- Phase 9 — tenant_billing_events: add organization_name for human traceability
-- =============================================================================
-- Adds organization_name TEXT so the billing table is human-readable without
-- requiring a JOIN to organizations. Backfilled column (nullable for existing rows).
-- =============================================================================

ALTER TABLE public.tenant_billing_events
  ADD COLUMN IF NOT EXISTS organization_name TEXT;

-- =============================================================================
-- Phase 9 — super_admin_create_organization: populate organization_name
--            and emit ORGANIZATION_CREATED to system_audit_log
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
  -- Service-role connections (migrations, Edge Functions) have auth.uid() = NULL;
  -- skip the claim check so integration tests using the service key work correctly.
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    v_is_super := auth.jwt() -> 'app_metadata' ->> 'super_admin';
    IF v_is_super IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
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
    p_super_admin_user_id,
    p_max_vehicles,
    p_max_active_contracts,
    NOW()
  );

  -- 5. Emit audit log entry (append-only via PG RULES)
  INSERT INTO public.system_audit_log (
    event_type,
    severity,
    payload,
    source,
    organization_id
  )
  VALUES (
    'ORGANIZATION_CREATED',
    'info',
    jsonb_build_object(
      'org_id',         v_org_id,
      'legal_name',     p_legal_name,
      'trade_name',     p_trade_name,
      'cnpj',           p_cnpj,
      'plan_type',      p_plan_type,
      'super_admin_id', p_super_admin_user_id
    ),
    'super_admin_rpc',
    v_org_id
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
