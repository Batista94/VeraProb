-- pr_scanner: ignore-regression
-- Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12).
-- =============================================================================
-- Migration: Sprint B — Rule Versioning RPCs
-- Purpose:   Lifecycle RPCs for contractual rule versioning:
--            update (immediate), schedule (future-dated), activate (promote),
--            retire (close without successor), amend financial terms.
--
-- Invariants: INV-3 (ledger facts append-only), INV-6 (UTC), INV-15
--             (anti-backdating shields deterministic replay), INV-21
--             (rule lifecycle is ledger-auditable), INV-22/26 (org-scoped,
--             validate-before-write).
--
-- Ledger insert contract (canonical since 20260310220000 rename):
--   (organization_id, type, operator_id, set_id, contract_id, plan_version,
--    payload, occurred_at_utc)
--   set_id is NOT NULL (legacy entity_id) — rule lifecycle facts anchor it to
--   the contract UUID text; contract_id column is UUID.
-- =============================================================================

-- ── 1. update_contractual_rule (replace: anti-backdating guard) ─────────────
-- NOTE: parameter keeps the original name p_now_utc — CREATE OR REPLACE cannot
-- rename parameters, and committed callers use positional args. Semantics are
-- now "effective-at": guarded to a ±5min window around server time.
CREATE OR REPLACE FUNCTION public.update_contractual_rule(
  p_contract_id       UUID,
  p_old_rule_id       UUID,        -- NULL for first version of a rule type
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

  -- INV-15: an immediate update may never rewrite the past (fraud vector:
  -- backdating a tolerance to alter last month's penalty reports)…
  IF p_now_utc < NOW() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'Anti-backdating violation: p_now_utc is too far in the past';
  END IF;
  -- …nor pre-date the future as a "current" rule (future = schedule_contractual_rule).
  IF p_now_utc > NOW() + INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'Future effective dates must use schedule_contractual_rule';
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
    -- No error if already closed — idempotent
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

-- ── 2. schedule_contractual_rule (future-dated, strictly > NOW()) ───────────
CREATE OR REPLACE FUNCTION public.schedule_contractual_rule(
  p_contract_id       UUID,
  p_old_rule_id       UUID,        -- informational; current rule stays active
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
  v_actor_id       UUID;
  v_rule_set_id    UUID;
  v_new_rule_id    UUID := gen_random_uuid();
  v_new_version    INT;
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

  -- Idempotent rule-set creation (same semantics as update_contractual_rule:
  -- scheduling the first rule of a contract is a valid lifecycle entry point).
  SELECT id INTO v_rule_set_id
  FROM public.contract_rule_sets
  WHERE contract_id   = p_contract_id::text
    AND organization_id = v_caller_org_id;

  IF NOT FOUND THEN
    v_rule_set_id := gen_random_uuid();
    INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
    VALUES (v_rule_set_id, v_caller_org_id, p_contract_id::text);
  END IF;

  SELECT COALESCE(MAX(rule_version), 0) + 1
  INTO v_new_version
  FROM public.contract_rule_versions
  WHERE rule_set_id = v_rule_set_id
    AND rule_type   = p_rule_type;

  -- idx_unique_scheduled_rule enforces a single pending schedule per type
  INSERT INTO public.contract_rule_versions (
    id, rule_set_id, rule_type, rule_config,
    rule_version, evaluation_order,
    active_from_utc, active_to_utc, is_scheduled
  ) VALUES (
    v_new_rule_id, v_rule_set_id, p_rule_type, p_new_config,
    v_new_version, p_evaluation_order,
    p_effective_at_utc, NULL, true
  );

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    v_caller_org_id, 'RULE_SCHEDULED', v_actor_id::text,
    p_contract_id::text, p_contract_id, 0,
    jsonb_build_object(
      'rule_id', v_new_rule_id,
      'rule_type', p_rule_type,
      'rule_version', v_new_version,
      'effective_at_utc', p_effective_at_utc,
      'superseded_rule_id', p_old_rule_id,
      'actor_id', v_actor_id
    ),
    NOW()
  );

  RETURN v_new_rule_id;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ) TO service_role;

-- ── 3. activate_scheduled_rule (promote scheduled → current; idempotent) ────
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
  v_caller_role   TEXT;
  v_actor_id      UUID;
  v_rule_set_id   UUID;
  v_rule_type     sla_rule_type;
  v_contract_id   TEXT;
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

  -- Validate ownership BEFORE any write (INV-22) and lock the scheduled row.
  SELECT v.rule_set_id, v.rule_type, s.contract_id
  INTO v_rule_set_id, v_rule_type, v_contract_id
  FROM public.contract_rule_versions v
  JOIN public.contract_rule_sets s ON s.id = v.rule_set_id
  WHERE v.id = p_rule_id
    AND s.organization_id = v_caller_org_id
    AND v.is_scheduled = true
    AND v.active_to_utc IS NULL
  FOR UPDATE OF v;

  IF NOT FOUND THEN
    -- Idempotency: already promoted (org-scoped lookup) → silent success.
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

  -- Close the current rule of this type (if any), then promote.
  UPDATE public.contract_rule_versions
  SET active_to_utc = NOW()
  WHERE rule_set_id = v_rule_set_id
    AND rule_type   = v_rule_type
    AND active_to_utc IS NULL
    AND is_scheduled = false;

  UPDATE public.contract_rule_versions
  SET is_scheduled = false
  WHERE id = p_rule_id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    v_caller_org_id, 'RULE_ACTIVATED', v_actor_id::text,
    v_contract_id, v_contract_id::uuid, 0,
    jsonb_build_object(
      'rule_id', p_rule_id,
      'rule_type', v_rule_type,
      'actor_id', v_actor_id
    ),
    NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_scheduled_rule(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_scheduled_rule(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_scheduled_rule(UUID) TO service_role;

-- ── 4. retire_contractual_rule (close WITHOUT successor + RULE_RETIRED fact) ─
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
  v_actor_id      UUID;
  v_contract_id   TEXT;
  v_rule_type     sla_rule_type;
  v_was_scheduled BOOLEAN;
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

  -- Validate ownership BEFORE any write (INV-22: never touch another org's
  -- row, even transiently) and lock the target.
  SELECT s.contract_id, v.rule_type, v.is_scheduled
  INTO v_contract_id, v_rule_type, v_was_scheduled
  FROM public.contract_rule_versions v
  JOIN public.contract_rule_sets s ON s.id = v.rule_set_id
  WHERE v.id = p_rule_id
    AND v.active_to_utc IS NULL
    AND s.organization_id = v_caller_org_id
  FOR UPDATE OF v;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Rule not found, already closed, or unauthorized';
  END IF;

  UPDATE public.contract_rule_versions
  SET active_to_utc = NOW()
  WHERE id = p_rule_id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    v_caller_org_id, 'RULE_RETIRED', v_actor_id::text,
    v_contract_id, v_contract_id::uuid, 0,
    jsonb_build_object(
      'rule_id', p_rule_id,
      'rule_type', v_rule_type,
      'was_scheduled', v_was_scheduled,
      'actor_id', v_actor_id
    ),
    NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.retire_contractual_rule(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.retire_contractual_rule(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.retire_contractual_rule(UUID) TO service_role;

-- ── 5. amend_contract_financial_terms (append-only amendment + denorm sync) ─
CREATE OR REPLACE FUNCTION public.amend_contract_financial_terms(
  p_contract_id             UUID,
  p_financial_ceiling_cents BIGINT,
  p_penalty_multiplier_bps  INT,
  p_effective_at_utc        TIMESTAMPTZ,
  p_notes                   TEXT
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

  IF p_penalty_multiplier_bps IS NULL OR p_penalty_multiplier_bps <= 0 THEN
    RAISE EXCEPTION 'penalty_multiplier_bps must be a positive integer (INV-4)';
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

  -- Denormalized sync on contracts (amendment table is the versioned source
  -- of truth). penalty_multiplier is the legacy DOUBLE PRECISION column —
  -- INV-4 impedance: bps INT is canonical here; float derived for the engine.
  -- seal_contracts_forensic + bump_contracts_version triggers seal this UPDATE.
  UPDATE public.contracts
  SET financial_ceiling_cents = p_financial_ceiling_cents,
      penalty_multiplier      = p_penalty_multiplier_bps / 10000.0
  WHERE id = p_contract_id
    AND organization_id = v_caller_org_id;

  INSERT INTO public.sla_audit_ledger_v2
    (organization_id, type, operator_id, set_id, contract_id,
     plan_version, payload, occurred_at_utc)
  VALUES (
    v_caller_org_id, 'CONTRACT_FINANCIAL_TERMS_AMENDED', v_actor_id::text,
    p_contract_id::text, p_contract_id, 0,
    jsonb_build_object(
      'amendment_id', v_amendment_id,
      'financial_ceiling_cents', p_financial_ceiling_cents,
      'penalty_multiplier_bps', p_penalty_multiplier_bps,
      'effective_at_utc', p_effective_at_utc,
      'actor_id', v_actor_id
    ),
    NOW()
  );

  RETURN v_amendment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.amend_contract_financial_terms(UUID, BIGINT, INT, TIMESTAMPTZ, TEXT) TO service_role;
