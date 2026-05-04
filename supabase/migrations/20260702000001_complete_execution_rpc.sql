-- =============================================================================
-- Migration: complete_execution RPC (Phase 10 — SLA Racing Guard)
--
-- Atomically transitions inTransit|planned → completed.
-- Uses compare-and-swap (WHERE status IN ...) as the optimistic lock primitive.
-- The DB-level trigger fsm_guard_terminal_states() is the safety net:
-- if two concurrent callers both pass the CAS, the trigger raises
-- restrict_violation on the second UPDATE — PostgreSQL serializes them.
--
-- INV-15: Deterministic — only one of N concurrent callers writes the
--         transition row. The winner returns TRUE; losers return FALSE.
-- INV-3:  Appends an immutable transition row to execution_state_transitions.
-- INV-26: Wrong-org scenario returns FALSE (indistinguishable from not-found).
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
  -- Fast idempotency check: already completed → return true without write.
  SELECT id, status
    INTO v_exec_id, v_prev_status
    FROM public.execution_states
   WHERE set_id          = p_set_id
     AND organization_id = p_org_id
   LIMIT 1;

  IF v_exec_id IS NULL THEN
    RETURN FALSE; -- Not found (INV-26: same as wrong-org)
  END IF;

  IF v_prev_status = 'completed' THEN
    RETURN TRUE; -- Already completed — first-wins idempotency (INV-15)
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
      'source',  'geofence_engine',
      'set_id',  p_set_id,
      'race_winner', TRUE
    )
  );

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_execution(UUID, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.complete_execution IS
  'Atomically transitions inTransit|planned → completed (CAS + FSM trigger guard). INV-15.';
