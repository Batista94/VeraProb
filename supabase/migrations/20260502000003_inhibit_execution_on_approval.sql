-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs (objects don't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Inhibition trigger + recomputation signal table (Phase 9.8.J)
--
-- When a contractor justification is APPROVED, this migration:
--   1. Extends the `execution_states.status` CHECK to include 'inhibited'.
--   2. Transitions the linked execution to 'inhibited' (suppresses penalty —
--      INV-13/INV-15).
--   3. Appends a row to `execution_state_transitions` for audit trail (INV-22).
--   4. INSERTs a `justification_recomputation_signals` row so the UI can show
--      "Pending Reconciliation" and Phase 9.8.K can drain the queue (PO-4).
--
-- NOTE: `contractual_financial_snapshot` is append-only and cannot be UPDATEd.
-- We deliberately do NOT couple to it here; Phase 9.8.K handles recomputation.
--
-- INV-7:  execution_state_transitions is append-only — trigger only INSERTs.
-- INV-9:  All timestamps UTC.
-- INV-13: INHIBITED = Innocent — no penalty accrues for this set_id.
-- INV-15: State inhibition suppresses penalty calculation.
-- INV-22: Every transition logged with justification_id in metadata.
-- =============================================================================

-- ── 1. Extend execution_states.status CHECK to include 'inhibited' ───────────

DO $$
BEGIN
  -- Drop the auto-named inline constraint from base_schema.sql.
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
     WHERE table_schema = 'public'
       AND table_name   = 'execution_states'
       AND constraint_name = 'execution_states_status_check'
  ) THEN
    ALTER TABLE public.execution_states
      DROP CONSTRAINT execution_states_status_check;
  END IF;

  -- Re-add with 'inhibited' included.
  ALTER TABLE public.execution_states
    ADD CONSTRAINT execution_states_status_check
      CHECK (status IN ('pending', 'executed', 'noShow', 'evidenceGap', 'inhibited'));
END
$$;

-- ── 2. justification_recomputation_signals ───────────────────────────────────
--
-- Lightweight dirty-flag table. A row here means the financial snapshot for
-- this contract_id / set_id combination needs recomputation after an approval.
-- The UI reads this to display "Pending Reconciliation" on affected rows.
-- Phase 9.8.K drains this table after recomputing the snapshot.
--
-- Append-only by design: DELETE is blocked; UPDATE is blocked.
-- Recomputation is signaled by adding a `resolved_at_utc` value via a
-- separate Phase 9.8.K migration.

CREATE TABLE IF NOT EXISTS public.justification_recomputation_signals (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  justification_id      UUID        NOT NULL
    REFERENCES public.contractor_justifications(id),
  organization_id       UUID        NOT NULL,
  contract_id           TEXT        NOT NULL,
  set_id                TEXT        NOT NULL,
  signaled_at_utc       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Phase 9.8.K stamps this when recomputation is complete.
  resolved_at_utc       TIMESTAMPTZ
);

COMMENT ON TABLE public.justification_recomputation_signals IS
  'deny-all: Internal trigger signals. service_role only.';

CREATE INDEX IF NOT EXISTS idx_jrs_contract_id
  ON public.justification_recomputation_signals (contract_id);

CREATE INDEX IF NOT EXISTS idx_jrs_set_id
  ON public.justification_recomputation_signals (set_id);

CREATE INDEX IF NOT EXISTS idx_jrs_unresolved
  ON public.justification_recomputation_signals (organization_id)
  WHERE resolved_at_utc IS NULL;

-- Append-only enforcement.
CREATE OR REPLACE FUNCTION public.prevent_jrs_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'justification_recomputation_signals is append-only. DELETE blocked. id: %', OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_jrs_no_delete
  ON public.justification_recomputation_signals;
CREATE TRIGGER trg_jrs_no_delete
  BEFORE DELETE ON public.justification_recomputation_signals
  FOR EACH ROW EXECUTE FUNCTION public.prevent_jrs_delete();

-- Lock all fields except resolved_at_utc.
CREATE OR REPLACE FUNCTION public.prevent_jrs_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.justification_id   IS DISTINCT FROM OLD.justification_id   OR
     NEW.organization_id    IS DISTINCT FROM OLD.organization_id    OR
     NEW.contract_id        IS DISTINCT FROM OLD.contract_id        OR
     NEW.set_id             IS DISTINCT FROM OLD.set_id             OR
     NEW.signaled_at_utc    IS DISTINCT FROM OLD.signaled_at_utc
  THEN
    RAISE EXCEPTION
      'justification_recomputation_signals: immutable field mutation. id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_jrs_no_immutable_update
  ON public.justification_recomputation_signals;
CREATE TRIGGER trg_jrs_no_immutable_update
  BEFORE UPDATE ON public.justification_recomputation_signals
  FOR EACH ROW EXECUTE FUNCTION public.prevent_jrs_immutable_mutation();

-- RLS
ALTER TABLE public.justification_recomputation_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS jrs_select_own_org
  ON public.justification_recomputation_signals;
CREATE POLICY jrs_select_own_org
  ON public.justification_recomputation_signals
  FOR SELECT
  USING (
    organization_id::text = (auth.jwt() ->> 'organization_id')
    AND (auth.jwt() ->> 'role') IN ('admin', 'operator', 'auditor')
  );

DROP POLICY IF EXISTS jrs_select_super_admin
  ON public.justification_recomputation_signals;
CREATE POLICY jrs_select_super_admin
  ON public.justification_recomputation_signals
  FOR SELECT
  USING (
    (auth.jwt() -> 'app_metadata' ->> 'super_admin')::boolean IS TRUE
  );

-- Service role inserts on behalf of the inhibition trigger.
DROP POLICY IF EXISTS jrs_insert_service
  ON public.justification_recomputation_signals;
CREATE POLICY jrs_insert_service
  ON public.justification_recomputation_signals
  FOR INSERT
  WITH CHECK (true);

-- Phase 9.8.K will use service role to stamp resolved_at_utc.
DROP POLICY IF EXISTS jrs_update_service
  ON public.justification_recomputation_signals;
CREATE POLICY jrs_update_service
  ON public.justification_recomputation_signals
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- ── 3. Inhibition trigger ────────────────────────────────────────────────────
--
-- Fires AFTER UPDATE on contractor_justifications when status becomes 'APPROVED'.
-- All three writes (execution_states, execution_state_transitions,
-- justification_recomputation_signals) execute in the same transaction.
--
-- SECURITY DEFINER: runs as the migration owner so it can bypass RLS on the
-- three target tables. This is intentional — the trigger is the only approved
-- write path for the inhibition state machine.

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
  -- Only fire when status transitions TO 'APPROVED'.
  IF NEW.status <> 'APPROVED' OR OLD.status = 'APPROVED' THEN
    RETURN NEW;
  END IF;

  -- ── Locate the execution state for this set_id + org. ───────────────────
  SELECT id, status
    INTO v_execution_id, v_prev_status
    FROM public.execution_states
   WHERE set_id          = NEW.set_id
     AND organization_id = NEW.organization_id
   LIMIT 1;

  -- If no matching execution exists (e.g., dev seed data), skip gracefully.
  IF v_execution_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- ── 3a. Inhibit the execution state. ────────────────────────────────────
  UPDATE public.execution_states
     SET status                    = 'inhibited',
         status_last_updated_at_utc = NOW()
   WHERE id = v_execution_id;

  -- ── 3b. Append a state transition entry (INV-22). ───────────────────────
  INSERT INTO public.execution_state_transitions (
    execution_state_id,
    previous_status,
    new_status,
    transitioned_at_utc,
    reason,
    metadata
  ) VALUES (
    v_execution_id,
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

  -- ── 3c. Signal financial snapshot for recomputation (PO-4). ─────────────
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

DROP TRIGGER IF EXISTS trg_inhibit_on_justification_approval
  ON public.contractor_justifications;
CREATE TRIGGER trg_inhibit_on_justification_approval
  AFTER UPDATE ON public.contractor_justifications
  FOR EACH ROW EXECUTE FUNCTION public.inhibit_execution_on_justification_approval();
