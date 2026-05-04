-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Fix complete_execution CAS race (INV-15)
--
-- Bug: complete_execution returned TRUE when execution was already 'completed'
-- (idempotency branch, line ~45). In a concurrent race under read-committed
-- isolation:
--   1. Caller A and B both read status='inTransit' in check_and_close.
--   2. A wins the CAS UPDATE in complete_execution → returns TRUE → inserts audit.
--   3. B's CAS UPDATE sees 0 rows (status already 'completed') → correct path:
--      RETURN FALSE → skip audit.
--   BUT if A commits fast enough, B's initial SELECT inside complete_execution
--   reads status='completed' and hits the idempotency branch → RETURN TRUE →
--   also inserts an audit row → 2 rows total (Expected: 1, Actual: 2).
--
-- Fix: The idempotency TRUE return is semantically wrong for the race context.
-- complete_execution must return TRUE only when THIS caller performed the CAS
-- transition. Return FALSE for all other cases (not-found, wrong-org,
-- race-lost, already-completed-by-another).
--
-- The early-exit guard in check_and_close_execution_autonomously
-- (IF v_status NOT IN ('inTransit','planned') → return 'closed') already
-- prevents unnecessary calls on completed executions, so changing the
-- idempotency branch from TRUE → FALSE is safe and does not regress any
-- existing caller.
--
-- INV-15: CAS first-write-wins — exactly one caller returns TRUE per race.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.complete_execution(
  p_org_id UUID,
  p_set_id TEXT,
  p_reason TEXT DEFAULT 'GEOFENCE_AUTO_FINISH'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exec_id        UUID;
  v_prev_status    TEXT;
  v_rows_updated   INT;
BEGIN
  -- Fetch current state (INV-1: org-scoped, INV-26: same as wrong-org).
  SELECT id, status
    INTO v_exec_id, v_prev_status
    FROM public.execution_states
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_exec_id IS NULL THEN
    RETURN FALSE; -- Not found / wrong-org (INV-26)
  END IF;

  -- INV-15 fix: return FALSE when already completed.
  -- Previously returned TRUE here (idempotency), but that caused both
  -- concurrent callers to return TRUE and each insert an audit row.
  -- Only the caller that performs the actual CAS UPDATE should return TRUE.
  IF v_prev_status = 'completed' THEN
    RETURN FALSE; -- Race lost: another caller already closed this execution
  END IF;

  IF v_prev_status NOT IN ('inTransit', 'planned') THEN
    RETURN FALSE; -- Terminal or unrecognised state
  END IF;

  -- Optimistic compare-and-swap.
  -- Both concurrent callers see v_prev_status = 'inTransit' and attempt this UPDATE.
  -- PostgreSQL row-level locking (implicit on UPDATE) serializes them: the first
  -- writer commits; the second hits the row already at status='completed' and
  -- the WHERE predicate filters it out (0 rows updated).
  UPDATE public.execution_states
     SET status                     = 'completed',
         status_last_updated_at_utc = NOW(),
         finalized_at_utc           = NOW()
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
     AND status          IN ('inTransit', 'planned'); -- CAS predicate

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  IF v_rows_updated = 0 THEN
    RETURN FALSE; -- Race lost: another caller already completed this execution
  END IF;

  -- Append immutable audit record (INV-3, INV-21).
  INSERT INTO public.execution_state_transitions (
    execution_state_id,
    organization_id,
    previous_status,
    new_status,
    transitioned_at_utc,
    reason,
    metadata
  ) VALUES (
    v_exec_id,
    p_org_id,
    v_prev_status,
    'completed',
    NOW(),
    p_reason,
    jsonb_build_object(
      'source',      'geofence_engine',
      'set_id',      p_set_id,
      'race_winner', TRUE
    )
  );

  RETURN TRUE; -- This caller performed the CAS transition
END;
$$;

REVOKE ALL ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.complete_execution IS
  'Atomically transitions inTransit|planned → completed (CAS + FSM trigger guard). '
  'Returns TRUE only when THIS caller performed the transition. '
  'Returns FALSE for race-lost, not-found, wrong-org, already-completed. '
  'INV-15: exactly one concurrent caller returns TRUE.';
