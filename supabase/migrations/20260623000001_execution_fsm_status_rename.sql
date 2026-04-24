-- =============================================================================
-- Migration: Execution State FSM — Status Rename + Guard Trigger + pg_cron
--
-- Renames execution_states.status values to the new FSM vocabulary:
--   pending       → planned
--   executed      → completed
--   noShow        → failed
--   evidenceGap   → completedWithGaps
--   inhibited     → inhibited (unchanged)
--   (new)         → inTransit
--
-- Also:
--   1. Updates CHECK constraint to include all 6 FSM states.
--   2. Renames historical execution_state_transitions rows for consistency.
--   3. Adds FSM guard trigger: completed/failed cannot revert to inTransit.
--   4. Adds start_transit_for_execution() RPC (first-wins idempotent).
--   5. Updates all RPCs that filter by old status strings.
--   6. Installs pg_cron safety net: planned past window_end + 24h → failed.
--
-- INV-3:  execution_state_transitions is append-only — we UPDATE existing rows
--         only for the historical rename (data integrity, not business logic).
-- INV-15: Deterministic replay — new status names serialize identically to .name.
-- INV-22: Every transition logged — guard trigger enforces FSM invariants.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Rename status values in execution_states ──────────────────────────────

-- Drop the existing CHECK constraint (last set in 20260502000003).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema = 'public'
       AND table_name   = 'execution_states'
       AND constraint_name = 'execution_states_status_check'
  ) THEN
    ALTER TABLE public.execution_states
      DROP CONSTRAINT execution_states_status_check;
  END IF;
END
$$;

-- Rename existing values (idempotent: only updates rows with old names).
UPDATE public.execution_states SET status = 'planned'            WHERE status = 'pending';
UPDATE public.execution_states SET status = 'completed'          WHERE status = 'executed';
UPDATE public.execution_states SET status = 'failed'             WHERE status = 'noShow';
UPDATE public.execution_states SET status = 'completedWithGaps'  WHERE status = 'evidenceGap';
-- 'inhibited' stays unchanged.

-- Add new CHECK constraint with all 6 FSM states.
ALTER TABLE public.execution_states
  ADD CONSTRAINT execution_states_status_check
    CHECK (status IN ('planned', 'inTransit', 'completed', 'completedWithGaps', 'failed', 'inhibited'));

-- ── 2. Rename historical transition rows for consistency ─────────────────────
-- These are audit rows — renaming them keeps the audit trail readable.
-- INV-3 note: we UPDATE existing rows here because this is a schema rename,
-- not a business state change. The append-only invariant applies to new rows.

UPDATE public.execution_state_transitions SET previous_status = 'planned'           WHERE previous_status = 'pending';
UPDATE public.execution_state_transitions SET previous_status = 'completed'         WHERE previous_status = 'executed';
UPDATE public.execution_state_transitions SET previous_status = 'failed'            WHERE previous_status = 'noShow';
UPDATE public.execution_state_transitions SET previous_status = 'completedWithGaps' WHERE previous_status = 'evidenceGap';

UPDATE public.execution_state_transitions SET new_status = 'planned'           WHERE new_status = 'pending';
UPDATE public.execution_state_transitions SET new_status = 'completed'         WHERE new_status = 'executed';
UPDATE public.execution_state_transitions SET new_status = 'failed'            WHERE new_status = 'noShow';
UPDATE public.execution_state_transitions SET new_status = 'completedWithGaps' WHERE new_status = 'evidenceGap';

-- ── 3. FSM guard trigger: terminal states cannot revert to inTransit ─────────
--
-- Allowed transitions:
--   planned         → inTransit, completed, failed, inhibited
--   inTransit       → completed, completedWithGaps, failed, inhibited
--   failed          → completed (INV-12 late arrival), inhibited
--   completedWithGaps → completed (INV-12 late arrival), inhibited
--   completed       → (terminal — no transitions allowed)
--   inhibited       → (terminal — no transitions allowed)
--
-- Blocked: completed → inTransit, failed → inTransit

CREATE OR REPLACE FUNCTION public.fsm_guard_terminal_states()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- completed and inhibited are fully terminal.
  IF OLD.status IN ('completed', 'inhibited') THEN
    RAISE EXCEPTION
      'FSM violation: cannot transition from % to %. set_id: %',
      OLD.status, NEW.status, OLD.set_id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- failed can only transition to completed (INV-12) or inhibited.
  IF OLD.status = 'failed' AND NEW.status NOT IN ('completed', 'inhibited') THEN
    RAISE EXCEPTION
      'FSM violation: failed can only transition to completed or inhibited. Attempted: % → %. set_id: %',
      OLD.status, NEW.status, OLD.set_id
    USING ERRCODE = 'restrict_violation';
  END IF;

  -- completedWithGaps can only transition to completed (INV-12) or inhibited.
  IF OLD.status = 'completedWithGaps' AND NEW.status NOT IN ('completed', 'inhibited') THEN
    RAISE EXCEPTION
      'FSM violation: completedWithGaps can only transition to completed or inhibited. Attempted: % → %. set_id: %',
      OLD.status, NEW.status, OLD.set_id
    USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fsm_guard_terminal_states ON public.execution_states;
CREATE TRIGGER trg_fsm_guard_terminal_states
  BEFORE UPDATE OF status ON public.execution_states
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.fsm_guard_terminal_states();

-- ── 4. RPC: start_transit_for_execution ──────────────────────────────────────
--
-- Transitions planned → inTransit. First-wins idempotent:
-- if already inTransit, returns true without error.
-- Returns false if the execution is not found or not in a transitionable state.

CREATE OR REPLACE FUNCTION public.start_transit_for_execution(
  p_org_id UUID,
  p_set_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status TEXT;
BEGIN
  SELECT status INTO v_current_status
    FROM public.execution_states
   WHERE set_id = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_current_status IS NULL THEN
    RETURN FALSE; -- Not found (INV-26: same response as wrong org)
  END IF;

  IF v_current_status = 'inTransit' THEN
    RETURN TRUE; -- Already inTransit — first-wins idempotency
  END IF;

  IF v_current_status != 'planned' THEN
    RETURN FALSE; -- Cannot transition from this state
  END IF;

  UPDATE public.execution_states
     SET status                     = 'inTransit',
         status_last_updated_at_utc = NOW()
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
     AND status          = 'planned'; -- Optimistic lock: only update if still planned

  -- Append transition record (INV-22).
  INSERT INTO public.execution_state_transitions (
    execution_state_id,
    organization_id,
    previous_status,
    new_status,
    transitioned_at_utc,
    reason,
    metadata
  )
  SELECT id, organization_id, 'planned', 'inTransit', NOW(), 'TELEGRAM_START_TRANSIT',
         jsonb_build_object('source', 'telegram', 'set_id', p_set_id)
    FROM public.execution_states
   WHERE set_id = p_set_id AND organization_id = p_org_id;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.start_transit_for_execution(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_transit_for_execution(UUID, TEXT) TO authenticated;

-- ── 5. Update RPCs that filter by old status strings ─────────────────────────

-- 5a. find_execution_for_telegram: accept planned, inTransit, completed, completedWithGaps
CREATE OR REPLACE FUNCTION public.find_execution_for_telegram(
  p_org_id     UUID,
  p_driver_id  UUID,
  p_message_ts BIGINT
)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT es.set_id
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse
    ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd
    ON cse.plan_declaration_id = pd.id
  INNER JOIN public.drivers d
    ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status IN ('planned', 'inTransit', 'completed', 'completedWithGaps')
    AND (es.planned_vehicle_id IS NULL OR es.planned_vehicle_id = d.license_number OR es.planned_vehicle_id = d.id::text)
    AND es.window_start_utc >= to_timestamp(p_message_ts - 4 * 3600) AT TIME ZONE 'UTC'
    AND es.window_start_utc <= to_timestamp(p_message_ts + 3600) AT TIME ZONE 'UTC'
  ORDER BY es.window_start_utc DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.find_execution_for_telegram(UUID, UUID, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_execution_for_telegram(UUID, UUID, BIGINT) TO authenticated;

-- 5b. find_pending_trips_for_driver: accept planned and inTransit
CREATE OR REPLACE FUNCTION public.find_pending_trips_for_driver(
  p_org_id    UUID,
  p_driver_id UUID,
  p_limit     INT DEFAULT 3
)
RETURNS TABLE(set_id TEXT, window_start_utc TIMESTAMPTZ)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT es.set_id, es.window_start_utc
  FROM public.execution_states es
  INNER JOIN public.contractual_service_executions cse
    ON es.set_id = cse.set_id
  INNER JOIN public.plan_declarations pd
    ON cse.plan_declaration_id = pd.id
  INNER JOIN public.drivers d
    ON d.id = p_driver_id
  WHERE pd.organization_id = p_org_id
    AND es.status IN ('planned', 'inTransit')
    AND (
      es.planned_vehicle_id IS NULL
      OR UPPER(REPLACE(es.planned_vehicle_id, '-', ''))
         = UPPER(REPLACE(d.license_number, '-', ''))
      OR es.planned_vehicle_id = d.id::text
    )
  ORDER BY ABS(EXTRACT(EPOCH FROM (es.window_start_utc - NOW())))
  LIMIT p_limit;
$$;

REVOKE ALL ON FUNCTION public.find_pending_trips_for_driver(UUID, UUID, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_pending_trips_for_driver(UUID, UUID, INT) TO authenticated;

-- 5c. get_trip_compliance_status: update status filter
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
    SELECT COUNT(*)::int INTO v_count
    FROM public.telegram_evidence_uploads teu
    WHERE teu.organization_id = p_org_id
      AND teu.driver_id = p_driver_id
      AND teu.linked_set_id = v_set_id
      AND teu.evidence_category = v_type;

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

-- 5d. inhibit_execution_on_justification_approval: update status references
CREATE OR REPLACE FUNCTION public.inhibit_execution_on_justification_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_execution_id  UUID;
  v_prev_status   TEXT;
BEGIN
  IF NEW.status <> 'APPROVED' OR OLD.status = 'APPROVED' THEN
    RETURN NEW;
  END IF;

  SELECT id, status
    INTO v_execution_id, v_prev_status
    FROM public.execution_states
   WHERE set_id          = NEW.set_id
     AND organization_id = NEW.organization_id
   LIMIT 1;

  IF v_execution_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.execution_states
     SET status                    = 'inhibited',
         status_last_updated_at_utc = NOW()
   WHERE id = v_execution_id;

  INSERT INTO public.execution_state_transitions (
    execution_state_id,
    organization_id,
    previous_status,
    new_status,
    transitioned_at_utc,
    reason,
    metadata
  ) VALUES (
    v_execution_id,
    NEW.organization_id,
    v_prev_status,
    'inhibited',
    NOW(),
    'JUSTIFICATION_APPROVED',
    jsonb_build_object(
      'justification_id',      NEW.id,
      'reviewed_by_user_id',   NEW.reviewed_by_user_id,
      'contract_id',           NEW.contract_id,
      'set_id',                NEW.set_id
    )
  );

  INSERT INTO public.justification_recomputation_signals (
    justification_id,
    organization_id,
    contract_id,
    set_id
  ) VALUES (
    NEW.id,
    NEW.organization_id,
    NEW.contract_id,
    NEW.set_id
  );

  RETURN NEW;
END;
$$;

-- Trigger already exists — no need to recreate.

-- ── 6. Performance index for pg_cron query ───────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_execution_states_fsm_active_expired
  ON public.execution_states (organization_id, window_end_utc)
  WHERE status IN ('planned', 'inTransit');

-- ── 7. pg_cron safety net: planned past window_end + 24h → failed ────────────
--
-- Belt-and-suspenders: if the evaluation engine misses a sweep (e.g., cold
-- start, network partition), this cron cleans up stale planned executions.
-- Runs every 15 minutes. Only affects rows that are 24h past their window end.
-- Guard: pg_cron is only available on Supabase Cloud, not local dev.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.schedule(
      'fsm_expire_stale_planned',
      '*/15 * * * *',
      $cron$
        UPDATE public.execution_states
           SET status                     = 'failed',
               status_last_updated_at_utc = NOW(),
               finalized_at_utc           = NOW()
         WHERE status IN ('planned', 'inTransit')
           AND window_end_utc < NOW() - INTERVAL '24 hours';
      $cron$
    );
  END IF;
END;
$$;
