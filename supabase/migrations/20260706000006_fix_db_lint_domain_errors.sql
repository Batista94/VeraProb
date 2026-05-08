-- =============================================================================
-- Fix: DB Lint Domain Errors (3 errors + 1 warning)
-- =============================================================================
-- MUST run AFTER 20260623000001 (which overwrites get_trip_compliance_status)
-- and AFTER 20260706000005 (latest migration).
--
-- 1. contractor_justifications missing resolution_notes column
-- 2. get_trip_compliance_status references teu.evidence_category (wrong table)
-- 3. super_admin_create_organization: v_actor_id/v_actor_email unused
--
-- INV-3:  Audit log actor_type now populated (forensic traceability).
-- INV-7:  telegram_evidence_uploads immutability preserved (JOIN, not ALTER).
-- INV-10: Runtime errors eliminated (resolution_notes, evidence_category).
-- INV-15: Deterministic compliance check restored.
-- =============================================================================

-- ══════════════════════════════════════════════════════════════════════════════
-- FIX 1: Add missing resolution_notes column to contractor_justifications
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.contractor_justifications
  ADD COLUMN IF NOT EXISTS resolution_notes TEXT;

COMMENT ON COLUMN public.contractor_justifications.resolution_notes IS
  'Free-text notes from reviewer when approving/rejecting justification.';

-- ══════════════════════════════════════════════════════════════════════════════
-- FIX 2: Recreate get_trip_compliance_status with correct JOIN
-- ══════════════════════════════════════════════════════════════════════════════
-- evidence_category lives in telegram_evidence_categories (separate table,
-- INV-7: telegram_evidence_uploads is fully immutable).

CREATE OR REPLACE FUNCTION public.get_trip_compliance_status(
  p_org_id    UUID,
  p_driver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_set_id        TEXT;
  v_contract_id   TEXT;
  v_rule_config    JSONB;
  v_required       TEXT[];
  v_items          JSONB := '[]'::jsonb;
  v_type           TEXT;
  v_count          INT;
  v_fulfilled      INT := 0;
  v_evidence_count INT;
  v_exec_status    TEXT;
BEGIN
  SELECT es.set_id, es.contract_id, es.status
  INTO v_set_id, v_contract_id, v_exec_status
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse
    ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd
    ON cse.plan_declaration_id = pd.id
  INNER JOIN public.drivers d
    ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status IN ('planned', 'inTransit', 'completed', 'completedWithGaps')
    AND (
      es.planned_vehicle_id IS NULL
      OR UPPER(REPLACE(es.planned_vehicle_id, '-', ''))
         = UPPER(REPLACE(d.license_number, '-', ''))
      OR es.planned_vehicle_id = d.id::text
    )
    AND es.window_start_utc >= NOW() - INTERVAL '4 hours'
    AND es.window_start_utc <= NOW() + INTERVAL '60 minutes'
  ORDER BY es.window_start_utc DESC
  LIMIT 1;

  IF v_set_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_active_trip');
  END IF;

  SELECT crv.rule_config
  INTO v_rule_config
  FROM public.contract_rule_sets crs
  INNER JOIN public.contract_rule_versions crv
    ON crv.rule_set_id = crs.id
  WHERE crs.contract_id = v_contract_id
    AND crs.organization_id = p_org_id
    AND crv.rule_type = 'REQUIRED_EVIDENCE'
    AND crv.active_to_utc IS NULL
  LIMIT 1;

  IF v_rule_config IS NULL THEN
    SELECT COUNT(*)::int INTO v_evidence_count
    FROM public.telegram_evidence_uploads teu
    WHERE teu.organization_id = p_org_id
      AND teu.driver_id = p_driver_id
      AND teu.linked_set_id = v_set_id;

    RETURN jsonb_build_object(
      'status', 'no_requirements',
      'set_id', v_set_id,
      'execution_status', v_exec_status,
      'evidence_count', v_evidence_count
    );
  END IF;

  SELECT ARRAY(
    SELECT jsonb_array_elements_text(v_rule_config -> 'types')
  ) INTO v_required;

  FOREACH v_type IN ARRAY v_required LOOP
    -- FIX: JOIN telegram_evidence_categories (category lives there, not in teu)
    SELECT COUNT(*)::int INTO v_count
    FROM public.telegram_evidence_uploads teu
    INNER JOIN public.telegram_evidence_categories tec
      ON tec.evidence_upload_id = teu.id
    WHERE teu.organization_id = p_org_id
      AND teu.driver_id = p_driver_id
      AND teu.linked_set_id = v_set_id
      AND tec.category = v_type;

    v_items := v_items || jsonb_build_object(
      'type_key', v_type,
      'is_fulfilled', v_count > 0,
      'count', v_count
    );

    IF v_count > 0 THEN
      v_fulfilled := v_fulfilled + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'active',
    'set_id', v_set_id,
    'execution_status', v_exec_status,
    'items', v_items,
    'total_required', array_length(v_required, 1),
    'total_fulfilled', v_fulfilled
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_trip_compliance_status(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_trip_compliance_status(UUID, UUID) TO authenticated;

-- ══════════════════════════════════════════════════════════════════════════════
-- FIX 3: super_admin_create_organization — use v_actor_id, add actor_type
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
);

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
  v_actor_type  TEXT;
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
    v_actor_id   := (auth.jwt() ->> 'sub')::uuid;
    v_actor_type := 'HUMAN';
  ELSE
    v_actor_id   := p_super_admin_user_id;
    v_actor_type := 'SYSTEM';
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

  -- ── Normalize allowed_domains ───────────────────────────────────────────────
  SELECT ARRAY(
    SELECT DISTINCT lower(trim(d))
    FROM unnest(p_allowed_domains) AS d
    WHERE trim(d) <> ''
    ORDER BY lower(trim(d))
  ) INTO v_normalized;

  -- ── Insert organization ─────────────────────────────────────────────────────
  INSERT INTO public.organizations (
    id, name, legal_name, cnpj, timezone, currency_code,
    plan_type, max_vehicles, max_active_contracts, capabilities,
    tool_cost_cents, dwell_time_seconds, billing_day, contact_email,
    external_id, organization_type, allowed_domains
  )
  VALUES (
    v_org_id, p_trade_name, p_legal_name,
    CASE WHEN trim(p_cnpj) = '' THEN NULL ELSE trim(p_cnpj) END,
    p_timezone, p_currency_code, p_plan_type, p_max_vehicles,
    p_max_active_contracts,
    COALESCE(p_capabilities, '{"allows_sealing": true, "allows_loading": true, "allows_cargo_check": true, "allows_incident": true, "allows_doc": true, "smart_classify": true}'::jsonb),
    p_tool_cost_cents, p_dwell_time_seconds, p_billing_day,
    p_contact_email, p_external_id, p_organization_type, v_normalized
  );

  -- ── Billing event (INV-7) ──────────────────────────────────────────────────
  INSERT INTO public.tenant_billing_events (
    organization_id, event_type, new_plan, changed_by_super_admin_id,
    new_max_vehicles, new_max_contracts, reason, occurred_at_utc
  )
  VALUES (
    v_org_id, 'ORG_CREATED', p_plan_type, p_super_admin_user_id,
    p_max_vehicles, p_max_active_contracts, p_reason, NOW()
  );

  -- ── Audit log (INV-3) ──────────────────────────────────────────────────────
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source,
    organization_id, organization_name, reason, actor_type
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
      ),
      'actor_id', v_actor_id
    ),
    'super_admin_rpc', v_org_id, p_trade_name, p_reason, v_actor_type
  );

  RETURN v_org_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, INT, UUID,
  JSONB, INT, INT, INT, TEXT, TEXT, TEXT, TEXT, text[]
) TO authenticated;
