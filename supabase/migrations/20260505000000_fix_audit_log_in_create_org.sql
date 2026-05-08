-- =============================================================================
-- Fix: Restore system_audit_log INSERT in super_admin_create_organization
-- =============================================================================
-- Migration 20260504000004 replaced the function to add p_allowed_domains but:
--   1. Omitted the INSERT INTO system_audit_log (ORGANIZATION_CREATE) statement
--   2. Inserted is_active = true into a GENERATED ALWAYS column (causes error)
--   3. Created a second overload causing PostgREST PGRST203 ambiguity
--
-- This migration:
--   - Drops BOTH existing overloads to eliminate ambiguity
--   - Creates a single correct function with p_allowed_domains support
--   - Removes is_active from the INSERT (generated column since 20260427010001)
--   - Restores actor resolution (v_actor_id, v_actor_email)
--   - Restores INSERT INTO system_audit_log with diff-format payload
--   - Drops the test helper function (cleanup from exploration tests)
--
-- INV-2:  SECURITY DEFINER + super_admin JWT claim validation preserved.
-- INV-3:  Audit log INSERT restored — forensic traceability.
-- INV-7:  Billing event (ORG_CREATED) is append-only — unchanged.
-- =============================================================================

-- ── Step 0: Drop test helper function (cleanup from exploration tests) ────────
DROP FUNCTION IF EXISTS public.test_drop_broken_create_org_overload();

-- ── Step 1: Drop ALL existing overloads to eliminate PostgREST ambiguity ──────
-- 17-param overload from migration 20260501000000
DROP FUNCTION IF EXISTS public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, INTEGER, INTEGER,
  JSONB, BIGINT, INTEGER, SMALLINT, TEXT, TEXT, TEXT, TEXT
);

-- 18-param overload from migration 20260504000004 (broken)
DROP FUNCTION IF EXISTS public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
);

-- ── Step 2: Create the fixed function ─────────────────────────────────────────
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
AS $fn$
DECLARE
  v_org_id      UUID := gen_random_uuid();
  v_actor_id    UUID;
  v_actor_email TEXT;
  v_normalized  text[];
BEGIN
  -- ── JWT validation ──────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    IF (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'Unauthorized: super_admin claim required'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- ── Actor resolution ────────────────────────────────────────────────────────
  IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
    v_actor_id    := (auth.jwt() ->> 'sub')::uuid;
    v_actor_email := auth.jwt() ->> 'email';
  ELSE
    -- Service-role bypass: fallback to provided super_admin_user_id
    v_actor_id    := p_super_admin_user_id;
    v_actor_email := 'system@veraprob.internal';
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
  -- NOTE: is_active is GENERATED ALWAYS AS (status = 'ACTIVE') since
  -- migration 20260427010001 — do NOT insert it explicitly.
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
    COALESCE(p_capabilities, '{"allows_sealing": true, "allows_loading": true, "allows_cargo_check": true, "allows_incident": true, "allows_doc": true, "smart_classify": true}'::jsonb),
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

  -- ── Append audit log entry (INV-3: forensic traceability) ───────────────────
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason
  )
  VALUES (
    'ORGANIZATION_CREATE', 'info',
    jsonb_build_object(
      'before', '{}'::jsonb,
      'after', jsonb_build_object(
        'legal_name',         p_legal_name,
        'trade_name',         p_trade_name,
        'cnpj',              p_cnpj,
        'plan_type',         p_plan_type,
        'max_vehicles',      p_max_vehicles,
        'tool_cost_cents',   p_tool_cost_cents,
        'billing_day',       p_billing_day,
        'contact_email',     p_contact_email,
        'external_id',       p_external_id,
        'organization_type', p_organization_type,
        'allowed_domains',   v_normalized
      )
    ),
    'super_admin_rpc', v_org_id, p_trade_name, p_reason
  );

  RETURN v_org_id;
END;
$fn$;

-- ── Step 3: Permissions ───────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) TO authenticated;
