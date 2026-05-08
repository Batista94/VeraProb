-- =============================================================================
-- Phase 10: super_admin_create_organization — add p_allowed_domains param
-- =============================================================================
-- Extends the existing create RPC to accept an initial allowed_domains list.
-- Preserves all existing behavior; p_allowed_domains defaults to '{}' so
-- callers that do not pass it continue to work without change.
--
-- INV-2:  SECURITY DEFINER + super_admin JWT claim validation preserved.
-- INV-7:  Billing event (ORG_CREATED) is append-only — unchanged.
-- Service-role bypass preserved: (auth.jwt() ->> 'sub') IS NULL = trusted.
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
  p_tool_cost_cents       INT      DEFAULT NULL,
  p_dwell_time_seconds    INT      DEFAULT 300,
  p_billing_day           INT      DEFAULT NULL,
  p_contact_email         TEXT     DEFAULT NULL,
  p_external_id           TEXT     DEFAULT NULL,
  p_reason                TEXT     DEFAULT NULL,
  p_organization_type     TEXT     DEFAULT NULL,
  p_allowed_domains       text[]   DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id     UUID := gen_random_uuid();
  v_normalized text[];
BEGIN
  -- ── JWT validation ──────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Input validation ────────────────────────────────────────────────────────
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

  -- ── Normalize allowed_domains (defense-in-depth) ───────────────────────────
  SELECT ARRAY(
    SELECT DISTINCT lower(trim(d))
    FROM unnest(p_allowed_domains) AS d
    WHERE trim(d) <> ''
    ORDER BY lower(trim(d))
  ) INTO v_normalized;

  -- ── Insert organization ─────────────────────────────────────────────────────
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
    is_active,
    capabilities,
    tool_cost_cents,
    dwell_time_seconds,
    billing_day,
    contact_email,
    external_id,
    organization_type,
    allowed_domains
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
    true,
    p_capabilities,
    p_tool_cost_cents,
    p_dwell_time_seconds,
    p_billing_day,
    p_contact_email,
    p_external_id,
    p_organization_type,
    v_normalized
  );

  -- ── Append immutable billing event (INV-7) ──────────────────────────────────
  INSERT INTO public.tenant_billing_events (
    organization_id,
    event_type,
    new_plan,
    changed_by_super_admin_id,
    new_max_vehicles,
    new_max_contracts,
    reason,
    occurred_at_utc
  )
  VALUES (
    v_org_id,
    'ORG_CREATED',
    p_plan_type,
    p_super_admin_user_id,
    p_max_vehicles,
    p_max_active_contracts,
    p_reason,
    NOW()
  );

  RETURN v_org_id;
END;
$$;

REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) TO authenticated;
