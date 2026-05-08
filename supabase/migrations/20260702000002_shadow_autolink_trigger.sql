-- =============================================================================
-- Migration: Shadow Auto-Link Trigger (Phase 10.3 — Fluid FSM)
--
-- When a new execution_states row is INSERTed (planned trip created),
-- this trigger retroactively links any UNLINKED_SHADOW evidences whose
-- message_ts falls within [window_start_utc, window_end_utc] and whose
-- organization_id matches.
--
-- This implements the "Fluid FSM" contract: evidence orphaned at ingestion
-- time can be retroactively bound to a trip created after the fact.
--
-- INV-3:  UNLINKED_SHADOW → RECONCILED appended to shadow_execution_transitions
--         via the existing auto_log_shadow_transition trigger (fires automatically).
-- INV-11: TDD gate — this migration is the implementation of the failing test
--         in k6_fluid_fsm_autolink.js (Phase 10.3).
-- INV-15: Idempotent — WHERE status = 'UNLINKED_SHADOW' + SKIP LOCKED prevents
--         double-link on concurrent INSERT + retry.
-- INV-22: organization_id filter throughout — Tenant-A cannot absorb Tenant-B's shadows.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.auto_link_shadows_to_execution()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_shadow         RECORD;
  v_window_start_s BIGINT;
  v_window_end_s   BIGINT;
BEGIN
  -- Guard: skip if window columns are NULL (partial execution rows).
  IF NEW.window_start_utc IS NULL OR NEW.window_end_utc IS NULL THEN
    RETURN NEW;
  END IF;

  -- Convert TIMESTAMPTZ to Unix seconds for comparison with message_ts (BIGINT).
  v_window_start_s := EXTRACT(EPOCH FROM NEW.window_start_utc)::BIGINT;
  v_window_end_s   := EXTRACT(EPOCH FROM NEW.window_end_utc)::BIGINT;

  -- Expand window by 30 minutes on each side to absorb early/late evidence.
  -- This matches the telegram find_execution_for_telegram temporal heuristic (INV-20).
  v_window_start_s := v_window_start_s - 1800; -- -30 min
  v_window_end_s   := v_window_end_s   + 1800; -- +30 min

  FOR v_shadow IN
    SELECT se.id, se.status, se.origin_evidence_id
      FROM public.shadow_executions se
     WHERE se.organization_id = NEW.organization_id
       AND se.status           = 'UNLINKED_SHADOW'
       AND se.message_ts       BETWEEN v_window_start_s AND v_window_end_s
     FOR UPDATE SKIP LOCKED  -- Skip rows locked by concurrent auto-link calls
  LOOP
    -- Transition UNLINKED_SHADOW → RECONCILED.
    -- The guard trigger (guard_shadow_execution_transitions) prevents regression.
    -- The auto_log_shadow_transition trigger appends to shadow_execution_transitions (INV-3).
    UPDATE public.shadow_executions
       SET status                  = 'RECONCILED',
           reconciled_execution_id = NEW.set_id,
           reconciled_at_utc       = NOW()
     WHERE id     = v_shadow.id
       AND status = 'UNLINKED_SHADOW'; -- Second CAS guard for concurrency safety
  END LOOP;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.auto_link_shadows_to_execution IS
  'Retroactively links UNLINKED_SHADOW evidence to newly created trips whose window covers the shadow message_ts. INV-11, INV-15, Phase 10.3.';

DROP TRIGGER IF EXISTS trg_auto_link_shadows ON public.execution_states;
CREATE TRIGGER trg_auto_link_shadows
  AFTER INSERT ON public.execution_states
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_link_shadows_to_execution();

-- ── Verification helper (call from SQL Editor after Scenario 4 test) ──────────
--
-- SELECT
--   se.id,
--   se.status,
--   se.reconciled_execution_id,
--   se.reconciled_at_utc,
--   se.message_ts,
--   es.window_start_utc,
--   es.window_end_utc
-- FROM shadow_executions se
-- JOIN execution_states es ON es.set_id = se.reconciled_execution_id
-- WHERE se.status = 'RECONCILED'
--   AND se.reconciled_at_utc > NOW() - INTERVAL '10 minutes'
-- ORDER BY se.reconciled_at_utc DESC;
-- Expected: all test shadows show reconciled_execution_id = the retroactive trip set_id.
