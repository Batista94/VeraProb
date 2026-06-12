-- =============================================================================
-- Migration: Sprint B — Rule Versioning RPCs
-- =============================================================================

-- 1. update_contractual_rule (replace)
CREATE OR REPLACE FUNCTION public.update_contractual_rule(
  p_contract_id       UUID,
  p_old_rule_id       UUID,        
  p_rule_type         sla_rule_type,
  p_new_config        JSONB,
  p_evaluation_order  INT,
  p_now_utc           TIMESTAMPTZ  DEFAULT NOW()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id  UUID;
  v_caller_role    TEXT;
  v_rule_set_id    UUID;
  v_new_rule_id    UUID := gen_random_uuid();
  v_new_version    INT;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  v_caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF v_caller_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  IF p_now_utc < NOW() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'Anti-backdating violation: p_now_utc is too far in the past';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.contracts
    WHERE id = p_contract_id
      AND organization_id = v_caller_org_id
  ) THEN
    RAISE EXCEPTION 'Contract not found or unauthorized. ID: %', p_contract_id;
  END IF;

  SELECT id INTO v_rule_set_id
  FROM public.contract_rule_sets
  WHERE contract_id   = p_contract_id::text
    AND organization_id = v_caller_org_id;

  IF NOT FOUND THEN
    v_rule_set_id := gen_random_uuid();
    INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
    VALUES (v_rule_set_id, v_caller_org_id, p_contract_id::text);
  END IF;

  IF p_old_rule_id IS NOT NULL THEN
    UPDATE public.contract_rule_versions
    SET active_to_utc = p_now_utc
    WHERE id          = p_old_rule_id
      AND rule_set_id = v_rule_set_id
      AND active_to_utc IS NULL;
  END IF;

  SELECT COALESCE(MAX(rule_version), 0) + 1
  INTO v_new_version
  FROM public.contract_rule_versions
  WHERE rule_set_id = v_rule_set_id
    AND rule_type   = p_rule_type;

  INSERT INTO public.contract_rule_versions (
    id, rule_set_id, rule_type, rule_config,
    rule_version, evaluation_order,
    active_from_utc, active_to_utc, is_scheduled
  ) VALUES (
    v_new_rule_id, v_rule_set_id, p_rule_type, p_new_config,
    v_new_version, p_evaluation_order,
    p_now_utc, NULL, false
  );

  RETURN v_new_rule_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) TO service_role;

-- 2. schedule_contractual_rule
CREATE OR REPLACE FUNCTION public.schedule_contractual_rule(
  p_contract_id       UUID,
  p_old_rule_id       UUID,        
  p_rule_type         sla_rule_type,
  p_new_config        JSONB,
  p_evaluation_order  INT,
  p_effective_at_utc  TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id  UUID;
  v_caller_role    TEXT;
  v_rule_set_id    UUID;
  v_new_rule_id    UUID := gen_random_uuid();
  v_new_version    INT;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  v_caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF v_caller_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  IF p_effective_at_utc <= NOW() THEN
    RAISE EXCEPTION 'Scheduled rules must be strictly in the future';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.contracts
    WHERE id = p_contract_id
      AND organization_id = v_caller_org_id
  ) THEN
    RAISE EXCEPTION 'Contract not found or unauthorized. ID: %', p_contract_id;
  END IF;

  SELECT id INTO v_rule_set_id
  FROM public.contract_rule_sets
  WHERE contract_id   = p_contract_id::text
    AND organization_id = v_caller_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cannot schedule rule for contract without an existing rule set';
  END IF;

  SELECT COALESCE(MAX(rule_version), 0) + 1
  INTO v_new_version
  FROM public.contract_rule_versions
  WHERE rule_set_id = v_rule_set_id
    AND rule_type   = p_rule_type;

  INSERT INTO public.contract_rule_versions (
    id, rule_set_id, rule_type, rule_config,
    rule_version, evaluation_order,
    active_from_utc, active_to_utc, is_scheduled
  ) VALUES (
    v_new_rule_id, v_rule_set_id, p_rule_type, p_new_config,
    v_new_version, p_evaluation_order,
    p_effective_at_utc, NULL, true
  );

  -- Log fact (Sprint B ledger types will be added next)
  INSERT INTO public.sla_audit_ledger_v2 (
    id, organization_id, type, contract_id, plan_version, occurred_at_utc, payload
  ) VALUES (
    gen_random_uuid(), v_caller_org_id, 'RULE_SCHEDULED',
    p_contract_id::text, 0, NOW(),
    jsonb_build_object('rule_id', v_new_rule_id, 'actor_id', (auth.jwt() ->> 'sub')::uuid)
  );

  RETURN v_new_rule_id;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) TO service_role;

-- 3. activate_scheduled_rule
CREATE OR REPLACE FUNCTION public.activate_scheduled_rule(
  p_rule_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id UUID;
  v_rule_set_id UUID;
  v_rule_type sla_rule_type;
  v_contract_id TEXT;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Validate ownership
  SELECT rule_set_id, rule_type, s.contract_id INTO v_rule_set_id, v_rule_type, v_contract_id
  FROM public.contract_rule_versions v
  JOIN public.contract_rule_sets s ON s.id = v.rule_set_id
  WHERE v.id = p_rule_id
    AND s.organization_id = v_caller_org_id
    AND v.is_scheduled = true;

  IF NOT FOUND THEN
    -- If already activated, idempotent, so we can just return
    IF EXISTS (
      SELECT 1 FROM public.contract_rule_versions v
      JOIN public.contract_rule_sets s ON s.id = v.rule_set_id
      WHERE v.id = p_rule_id
        AND s.organization_id = v_caller_org_id
        AND v.is_scheduled = false
    ) THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Scheduled rule not found or unauthorized';
  END IF;

  -- Close existing active rule for this type
  UPDATE public.contract_rule_versions
  SET active_to_utc = NOW()
  WHERE rule_set_id = v_rule_set_id
    AND rule_type = v_rule_type
    AND active_to_utc IS NULL
    AND is_scheduled = false;

  -- Activate the scheduled rule
  UPDATE public.contract_rule_versions
  SET is_scheduled = false
  WHERE id = p_rule_id;

  INSERT INTO public.sla_audit_ledger_v2 (
    id, organization_id, type, contract_id, plan_version, occurred_at_utc, payload
  ) VALUES (
    gen_random_uuid(), v_caller_org_id, 'RULE_ACTIVATED',
    v_contract_id, 0, NOW(),
    jsonb_build_object('rule_id', p_rule_id, 'actor_id', (auth.jwt() ->> 'sub')::uuid)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_scheduled_rule(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_scheduled_rule(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_scheduled_rule(UUID) TO service_role;

-- 4. retire_contractual_rule
CREATE OR REPLACE FUNCTION public.retire_contractual_rule(
  p_rule_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id UUID;
  v_caller_role   TEXT;
  v_contract_id   TEXT;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  v_caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF v_caller_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  -- Validate and close
  UPDATE public.contract_rule_versions
  SET active_to_utc = NOW()
  WHERE id = p_rule_id
    AND active_to_utc IS NULL
  RETURNING (
    SELECT s.contract_id 
    FROM public.contract_rule_sets s 
    WHERE s.id = rule_set_id 
      AND s.organization_id = v_caller_org_id
  ) INTO v_contract_id;

  IF v_contract_id IS NULL THEN
    RAISE EXCEPTION 'Rule not found, already closed, or unauthorized';
  END IF;

  INSERT INTO public.sla_audit_ledger_v2 (
    id, organization_id, type, contract_id, plan_version, occurred_at_utc, payload
  ) VALUES (
    gen_random_uuid(), v_caller_org_id, 'RULE_RETIRED',
    v_contract_id, 0, NOW(),
    jsonb_build_object('rule_id', p_rule_id, 'actor_id', (auth.jwt() ->> 'sub')::uuid)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.retire_contractual_rule(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.retire_contractual_rule(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.retire_contractual_rule(UUID) TO service_role;

-- 5. amend_contract_financial_terms
CREATE OR REPLACE FUNCTION public.amend_contract_financial_terms(
  p_contract_id           UUID,
  p_financial_ceiling_cents BIGINT,
  p_penalty_multiplier_bps  INT,
  p_effective_at_utc      TIMESTAMPTZ,
  p_notes                 TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id  UUID;
  v_caller_role    TEXT;
  v_amendment_id   UUID := gen_random_uuid();
  v_actor_id       UUID;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
  v_caller_role   := auth.jwt() -> 'app_metadata' ->> 'role';
  v_actor_id      := (auth.jwt() ->> 'sub')::uuid;

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  IF v_caller_role <> 'TENANT_ADMIN' THEN
    RAISE EXCEPTION 'Unauthorized: TENANT_ADMIN role required';
  END IF;

  IF p_effective_at_utc < NOW() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'Anti-backdating violation: p_effective_at_utc is too far in the past';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.contracts
    WHERE id = p_contract_id
      AND organization_id = v_caller_org_id
  ) THEN
    RAISE EXCEPTION 'Contract not found or unauthorized';
  END IF;

  INSERT INTO public.contract_financial_amendments (
    id, organization_id, contract_id, financial_ceiling_cents,
    penalty_multiplier_bps, effective_at_utc, amended_at_utc,
    amended_by_user_id, notes
  ) VALUES (
    v_amendment_id, v_caller_org_id, p_contract_id::text, p_financial_ceiling_cents,
    p_penalty_multiplier_bps, p_effective_at_utc, NOW(),
    v_actor_id, p_notes
  );

  -- Denormalized update on contracts. Note: financial_ceiling_cents and penalty_multiplier_bps columns 
  -- need to exist. The instructions say we fix impedancia INV-4 do float.
  UPDATE public.contracts
  SET penalty_multiplier_bps = p_penalty_multiplier_bps
  WHERE id = p_contract_id;

  INSERT INTO public.sla_audit_ledger_v2 (
    id, organization_id, type, contract_id, plan_version, occurred_at_utc, payload
  ) VALUES (
    gen_random_uuid(), v_caller_org_id, 'CONTRACT_FINANCIAL_TERMS_AMENDED',
    p_contract_id::text, 0, NOW(),
    jsonb_build_object('amendment_id', v_amendment_id, 'actor_id', v_actor_id)
  );

  RETURN v_amendment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT) TO service_role;
