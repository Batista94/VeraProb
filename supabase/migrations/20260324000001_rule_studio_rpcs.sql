-- ============================================================
-- veraprob — Phase 6 Block 7: Rule Configuration Studio
-- Sprint 6.7 | 2026-03-17
-- ============================================================
-- Changes:
--   1. Fix rule_config_schema_check constraint (align with engine's actual keys)
--   2. RPC: update_contractual_rule (atomic version transition, TENANT_ADMIN)
--   3. RPC: get_rule_version_history (read-only audit trail per contract)
-- ============================================================

-- ── 1. Fix rule_config_schema_check constraint ────────────────────────────
-- The original constraint (20260305175500) used keys that diverge from what
-- the ContractualEvaluationEngine actually reads at runtime:
--   - MIN_GEOFENCE_COVERAGE: engine reads 'min_dwell_seconds' (not 'min_coverage_pct')
--   - NO_SHOW_PENALTY:       engine reads 'penalty_amount_cents' (not 'multiplier_value')
-- This fix aligns the DB constraint with the engine's config contract.

ALTER TABLE public.contract_rule_versions
  DROP CONSTRAINT IF EXISTS rule_config_schema_check;

ALTER TABLE public.contract_rule_versions
  ADD CONSTRAINT rule_config_schema_check CHECK (
    (rule_type = 'MAX_TOLERANCE_DELAY'   AND rule_config ? 'threshold_minutes')    OR
    (rule_type = 'MAX_EVIDENCE_GAP'      AND rule_config ? 'max_gap_seconds')       OR
    (rule_type = 'MIN_GEOFENCE_COVERAGE' AND rule_config ? 'min_dwell_seconds')     OR
    (rule_type = 'NO_SHOW_PENALTY'       AND rule_config ? 'penalty_amount_cents')
  );

-- ── 2. RPC: update_contractual_rule ──────────────────────────────────────
-- TENANT_ADMIN only. Atomically:
--   1. Validates caller org context from JWT
--   2. Creates contract_rule_sets row if not yet present (idempotent)
--   3. Closes old active version (active_to_utc = p_now_utc) if p_old_rule_id provided
--   4. Inserts new active version with next sequential rule_version
--   5. Returns the new rule UUID
--
-- Business logic (which rule to update, validation) lives in Dart handler.
-- This RPC is ONLY an atomicity guarantee — no business rules here (INV-4).
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

  -- Validate that the target contract belongs to the caller's org
  IF NOT EXISTS (
    SELECT 1 FROM public.contracts
    WHERE id = p_contract_id
      AND organization_id = v_caller_org_id
  ) THEN
    RAISE EXCEPTION 'Contract not found or unauthorized. ID: %', p_contract_id;
  END IF;

  -- Get or create rule set for this contract (idempotent)
  SELECT id INTO v_rule_set_id
  FROM public.contract_rule_sets
  WHERE contract_id   = p_contract_id::text
    AND organization_id = v_caller_org_id;

  IF NOT FOUND THEN
    v_rule_set_id := gen_random_uuid();
    INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
    VALUES (v_rule_set_id, v_caller_org_id, p_contract_id::text);
  END IF;

  -- Close old active version if provided
  IF p_old_rule_id IS NOT NULL THEN
    UPDATE public.contract_rule_versions
    SET active_to_utc = p_now_utc
    WHERE id          = p_old_rule_id
      AND rule_set_id = v_rule_set_id
      AND active_to_utc IS NULL;
    -- No error if already closed — idempotent
  END IF;

  -- Determine next version number (per rule_type within the set)
  SELECT COALESCE(MAX(rule_version), 0) + 1
  INTO v_new_version
  FROM public.contract_rule_versions
  WHERE rule_set_id = v_rule_set_id
    AND rule_type   = p_rule_type;

  -- Insert new active version
  -- The unique index idx_unique_active_rule_type enforces single active version per type
  INSERT INTO public.contract_rule_versions (
    id, rule_set_id, rule_type, rule_config,
    rule_version, evaluation_order,
    active_from_utc, active_to_utc
  ) VALUES (
    v_new_rule_id, v_rule_set_id, p_rule_type, p_new_config,
    v_new_version, p_evaluation_order,
    p_now_utc, NULL
  );

  RETURN v_new_rule_id;
END;
$$;

REVOKE ALL ON FUNCTION public.update_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ)
  FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.update_contractual_rule(UUID, UUID, sla_rule_type, JSONB, INT, TIMESTAMPTZ)
  TO authenticated;

-- ── 3. RPC: get_rule_version_history ─────────────────────────────────────
-- Authenticated (any org member). Returns all rule versions for a contract
-- sorted by rule_type + version descending (newest first per type).
-- Used by the Rule Studio's Version History Panel (read-only audit trail).
CREATE OR REPLACE FUNCTION public.get_rule_version_history(
  p_contract_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org_id  UUID;
  v_result         JSONB;
BEGIN
  v_caller_org_id := (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;

  IF v_caller_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: no organization context in JWT';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',               v.id,
      'rule_type',        v.rule_type,
      'rule_config',      v.rule_config,
      'rule_version',     v.rule_version,
      'evaluation_order', v.evaluation_order,
      'active_from_utc',  v.active_from_utc,
      'active_to_utc',    v.active_to_utc,
      'is_active',        (v.active_to_utc IS NULL)
    )
    ORDER BY v.rule_type, v.rule_version DESC
  )
  INTO v_result
  FROM public.contract_rule_sets   rs
  JOIN public.contract_rule_versions v ON v.rule_set_id = rs.id
  WHERE rs.contract_id    = p_contract_id::text
    AND rs.organization_id = v_caller_org_id;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.get_rule_version_history(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_rule_version_history(UUID) TO authenticated;
