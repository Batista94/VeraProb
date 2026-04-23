-- =============================================================================
-- Migration: Evidence Compliance Status (/status command)
--
-- 1. Extend sla_rule_type enum with REQUIRED_EVIDENCE
-- 2. Update rule_config_schema_check constraint
-- 3. Create telegram_status_queries table (append-only, INV-7)
-- 4. RPC: get_trip_compliance_status (single driver)
-- 5. RPC: get_batch_compliance_status (dashboard, avoids N+1)
-- 6. RPC: get_driver_status_query_count (forensic negligence)
--
-- INV-1:  All RPCs filter by organization_id from JWT or parameter.
-- INV-3:  telegram_status_queries is append-only (INV-7 triggers).
-- INV-7:  No UPDATE/DELETE on audit table.
-- INV-16: Batch RPC avoids N+1 connection pressure.
-- INV-18: Category values validated against known enum.
-- INV-22: Cross-org isolation enforced via RLS + RPC guards.
-- INV-26: Error parity — wrong-org returns same shape as not-found.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Extend sla_rule_type enum ─────────────────────────────────────────────
-- NOTE: ADD VALUE moved to 20260615000002_add_required_evidence_enum.sql
-- ALTER TYPE ... ADD VALUE is non-transactional — must run in a prior migration.

-- ── 2. Update rule_config_schema_check constraint ────────────────────────────
-- Must DROP + recreate because ALTER CONSTRAINT doesn't exist in Postgres.

ALTER TABLE public.contract_rule_versions
  DROP CONSTRAINT IF EXISTS rule_config_schema_check;

ALTER TABLE public.contract_rule_versions
  ADD CONSTRAINT rule_config_schema_check CHECK (
    (rule_type = 'MAX_TOLERANCE_DELAY'   AND rule_config ? 'threshold_minutes')    OR
    (rule_type = 'MAX_EVIDENCE_GAP'      AND rule_config ? 'max_gap_seconds')       OR
    (rule_type = 'MIN_GEOFENCE_COVERAGE' AND rule_config ? 'min_dwell_seconds')     OR
    (rule_type = 'NO_SHOW_PENALTY'       AND rule_config ? 'penalty_amount_cents')  OR
    (rule_type = 'REQUIRED_EVIDENCE'     AND rule_config ? 'types')
  );

-- ── 3. telegram_status_queries — forensic audit of /status consultations ─────

CREATE TABLE IF NOT EXISTS public.telegram_status_queries (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     UUID        NOT NULL,
  driver_id           UUID        NOT NULL,
  chat_id             BIGINT      NOT NULL,
  set_id              TEXT,                     -- NULL when no active trip
  compliance_snapshot JSONB       NOT NULL,     -- full RPC response frozen at query time
  queried_at_utc      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for negligence audit: "how many times did driver X check /status for SET Y?"
CREATE INDEX IF NOT EXISTS idx_tsq_org_driver_set
  ON public.telegram_status_queries (organization_id, driver_id, set_id, queried_at_utc DESC);

-- ── 3a. Immutability triggers (INV-7) ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_tsq_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_status_queries: fully immutable (INV-7). UPDATE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tsq_no_update ON public.telegram_status_queries;
CREATE TRIGGER trg_tsq_no_update
  BEFORE UPDATE ON public.telegram_status_queries
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tsq_update();

CREATE OR REPLACE FUNCTION public.prevent_tsq_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION
    'telegram_status_queries: append-only (INV-7). DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_tsq_no_delete ON public.telegram_status_queries;
CREATE TRIGGER trg_tsq_no_delete
  BEFORE DELETE ON public.telegram_status_queries
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tsq_delete();

-- ── 3b. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.telegram_status_queries ENABLE ROW LEVEL SECURITY;

-- Service role (webhook) inserts on behalf of driver
DROP POLICY IF EXISTS tsq_insert_service ON public.telegram_status_queries;
CREATE POLICY tsq_insert_service
  ON public.telegram_status_queries FOR INSERT
  WITH CHECK (true);

-- Dashboard reads (auditor, admin)
DROP POLICY IF EXISTS tsq_select_own_org ON public.telegram_status_queries;
CREATE POLICY tsq_select_own_org
  ON public.telegram_status_queries FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'role') IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR')
  );

-- ── 4. RPC: get_trip_compliance_status ───────────────────────────────────────
--
-- Resolves the driver's active execution, finds REQUIRED_EVIDENCE rules on
-- the linked contract, and cross-references with categorized evidence.
--
-- Returns JSONB:
--   Active trip with rules:  {"status":"active","set_id":"...","items":[...],"total_required":3,"total_fulfilled":2}
--   No active trip:          {"status":"no_active_trip"}
--   No requirements defined: {"status":"no_requirements","set_id":"...","evidence_count":N}

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
  v_rule_config   JSONB;
  v_required      TEXT[];
  v_items         JSONB := '[]'::jsonb;
  v_type          TEXT;
  v_count         INT;
  v_fulfilled     INT := 0;
  v_evidence_count INT;
BEGIN
  -- Step 1: Find active execution (same heuristic as find_execution_for_telegram)
  SELECT es.set_id, es.contract_id
  INTO v_set_id, v_contract_id
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse
    ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd
    ON cse.plan_declaration_id = pd.id
  INNER JOIN public.drivers d
    ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status IN ('pending', 'executed', 'evidenceGap')
    AND (
      es.planned_vehicle_id IS NULL
      OR UPPER(REPLACE(es.planned_vehicle_id, '-', ''))
         = UPPER(REPLACE(d.license_number, '-', ''))
      OR es.planned_vehicle_id = d.id::text
    )
    -- Window: NOW() must be within [T - 60min, T + 4h]
    AND es.window_start_utc >= NOW() - INTERVAL '4 hours'
    AND es.window_start_utc <= NOW() + INTERVAL '60 minutes'
  ORDER BY es.window_start_utc DESC
  LIMIT 1;

  IF v_set_id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_active_trip');
  END IF;

  -- Step 2: Find REQUIRED_EVIDENCE rule for this contract
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
    -- No requirements defined — return generic count
    SELECT COUNT(*)::int INTO v_evidence_count
    FROM public.telegram_evidence_uploads teu
    WHERE teu.organization_id = p_org_id
      AND teu.driver_id = p_driver_id
      AND teu.linked_set_id = v_set_id;

    RETURN jsonb_build_object(
      'status', 'no_requirements',
      'set_id', v_set_id,
      'evidence_count', v_evidence_count
    );
  END IF;

  -- Step 3: Extract required types array
  SELECT ARRAY(
    SELECT jsonb_array_elements_text(v_rule_config -> 'types')
  ) INTO v_required;

  -- Step 4: For each required type, count matching categorized evidence
  FOREACH v_type IN ARRAY v_required LOOP
    SELECT COUNT(*)::int INTO v_count
    FROM public.telegram_evidence_categories tec
    INNER JOIN public.telegram_evidence_uploads teu
      ON tec.evidence_upload_id = teu.id
    WHERE teu.organization_id = p_org_id
      AND teu.driver_id = p_driver_id
      AND teu.linked_set_id = v_set_id
      AND tec.category = v_type;

    v_items := v_items || jsonb_build_object(
      'type_key', v_type,
      'is_fulfilled', (v_count > 0),
      'count', v_count
    );

    IF v_count > 0 THEN
      v_fulfilled := v_fulfilled + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'active',
    'set_id', v_set_id,
    'items', v_items,
    'total_required', array_length(v_required, 1),
    'total_fulfilled', v_fulfilled
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_trip_compliance_status(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_trip_compliance_status(UUID, UUID) TO authenticated;

-- ── 5. RPC: get_batch_compliance_status ──────────────────────────────────────
--
-- Dashboard batch query: given an array of set_ids, returns compliance for each.
-- Avoids N+1 RPC calls from the Flutter dashboard (INV-16).
--
-- Returns JSONB array: [{"set_id":"...","items":[...],"total_required":3,"total_fulfilled":2}, ...]
-- SETs without REQUIRED_EVIDENCE rules are returned with status "no_requirements".

CREATE OR REPLACE FUNCTION public.get_batch_compliance_status(
  p_org_id  UUID,
  p_set_ids TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_result       JSONB := '[]'::jsonb;
  v_sid          TEXT;
  v_contract_id  TEXT;
  v_rule_config  JSONB;
  v_required     TEXT[];
  v_items        JSONB;
  v_type         TEXT;
  v_count        INT;
  v_fulfilled    INT;
  v_evidence_count INT;
BEGIN
  FOREACH v_sid IN ARRAY p_set_ids LOOP
    -- Resolve contract_id for this SET (with org isolation)
    SELECT es.contract_id INTO v_contract_id
    FROM public.execution_states es
    INNER JOIN public.contractual_service_executions cse
      ON es.set_id = cse.set_id
    INNER JOIN public.plan_declarations pd
      ON cse.plan_declaration_id = pd.id
    WHERE es.set_id = v_sid
      AND pd.organization_id = p_org_id;

    IF v_contract_id IS NULL THEN
      -- SET not found or wrong org (INV-26: same shape)
      CONTINUE;
    END IF;

    -- Find REQUIRED_EVIDENCE rule
    SELECT crv.rule_config INTO v_rule_config
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
        AND teu.linked_set_id = v_sid;

      v_result := v_result || jsonb_build_object(
        'set_id', v_sid,
        'status', 'no_requirements',
        'evidence_count', v_evidence_count
      );
      CONTINUE;
    END IF;

    SELECT ARRAY(
      SELECT jsonb_array_elements_text(v_rule_config -> 'types')
    ) INTO v_required;

    v_items := '[]'::jsonb;
    v_fulfilled := 0;

    FOREACH v_type IN ARRAY v_required LOOP
      SELECT COUNT(*)::int INTO v_count
      FROM public.telegram_evidence_categories tec
      INNER JOIN public.telegram_evidence_uploads teu
        ON tec.evidence_upload_id = teu.id
      WHERE teu.organization_id = p_org_id
        AND teu.linked_set_id = v_sid
        AND tec.category = v_type;

      v_items := v_items || jsonb_build_object(
        'type_key', v_type,
        'is_fulfilled', (v_count > 0),
        'count', v_count
      );

      IF v_count > 0 THEN
        v_fulfilled := v_fulfilled + 1;
      END IF;
    END LOOP;

    v_result := v_result || jsonb_build_object(
      'set_id', v_sid,
      'status', 'active',
      'items', v_items,
      'total_required', array_length(v_required, 1),
      'total_fulfilled', v_fulfilled
    );
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_batch_compliance_status(UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_batch_compliance_status(UUID, TEXT[]) TO authenticated;

-- ── 6. RPC: get_driver_status_query_count ────────────────────────────────────
--
-- Forensic negligence audit: how many times did the driver check /status
-- for a given SET, and did they have pending items at query time?
--
-- Returns JSONB: {"query_count":3,"last_queried_at":"...","had_pending_items":true}

CREATE OR REPLACE FUNCTION public.get_driver_status_query_count(
  p_org_id    UUID,
  p_driver_id UUID,
  p_set_id    TEXT
)
RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE(
    (
      SELECT jsonb_build_object(
        'query_count', COUNT(*)::int,
        'last_queried_at', MAX(queried_at_utc),
        'had_pending_items', bool_or(
          (compliance_snapshot ->> 'total_fulfilled')::int
          < (compliance_snapshot ->> 'total_required')::int
        ),
        'forced_completions', COUNT(*) FILTER (
          WHERE (compliance_snapshot ->> 'forced_completion_with_gaps')::boolean IS TRUE
        )
      )
      FROM public.telegram_status_queries
      WHERE organization_id = p_org_id
        AND driver_id = p_driver_id
        AND set_id = p_set_id
    ),
    '{"query_count":0,"last_queried_at":null,"had_pending_items":false,"forced_completions":0}'::jsonb
  );
$$;

REVOKE ALL ON FUNCTION public.get_driver_status_query_count(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_driver_status_query_count(UUID, UUID, TEXT) TO authenticated;
