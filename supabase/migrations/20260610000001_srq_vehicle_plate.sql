SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Add vehicle_plate to sanction_review_queue (Phase 10.4 WS-6)
--
-- Denormalizes the vehicle plate at insert time via the enqueue trigger.
-- Enables cheap monthly recurrence queries without runtime JOINs.
--
-- INV-1: vehicle_plate is treated as immutable (added to the guard trigger).
-- INV-9: All date comparisons in recurrence queries use UTC timestamps.
-- =============================================================================

-- ── A: Add column ─────────────────────────────────────────────────────────────
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS vehicle_plate TEXT NULL;

-- ── B: Partial index for recurrence queries (org + plate + month window) ──────
CREATE INDEX IF NOT EXISTS idx_srq_org_plate_created
  ON public.sanction_review_queue (organization_id, vehicle_plate, created_at)
  WHERE vehicle_plate IS NOT NULL;

-- ── C: Update immutability trigger to guard vehicle_plate ─────────────────────
-- The plate is forensic context — once set at insert time it must not drift.
CREATE OR REPLACE FUNCTION public.prevent_srq_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.organization_id   IS DISTINCT FROM OLD.organization_id   OR
     NEW.ledger_entry_id   IS DISTINCT FROM OLD.ledger_entry_id   OR
     NEW.set_id            IS DISTINCT FROM OLD.set_id            OR
     NEW.contract_id       IS DISTINCT FROM OLD.contract_id       OR
     NEW.verdict_evidence  IS DISTINCT FROM OLD.verdict_evidence  OR
     NEW.created_at        IS DISTINCT FROM OLD.created_at        OR
     NEW.vehicle_plate     IS DISTINCT FROM OLD.vehicle_plate
  THEN
    RAISE EXCEPTION
      'sanction_review_queue: immutable field mutation attempted (INV-1). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

-- ── D: Update enqueue trigger to resolve and store vehicle plate ───────────────
-- Joins execution_states → vehicles at INSERT time (after engine evaluation,
-- the vehicle should already be bound). Resolves to NULL gracefully when
-- set_id is unknown or the vehicle is unbound — the column is nullable.
CREATE OR REPLACE FUNCTION public.auto_enqueue_sanction_recommended()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_vehicle_plate TEXT;
BEGIN
  IF NEW.type = 'SANCTION_RECOMMENDED' THEN
    -- Resolve vehicle plate via execution state → vehicle registry
    SELECT v.plate INTO v_vehicle_plate
    FROM public.execution_states es
    JOIN public.vehicles v
      ON v.id::text = es.bound_vehicle_id
     AND v.organization_id = NEW.organization_id
    WHERE es.set_id = COALESCE(NEW.set_id, '')
      AND es.organization_id = NEW.organization_id
    LIMIT 1;

    INSERT INTO public.sanction_review_queue (
      organization_id,
      ledger_entry_id,
      set_id,
      contract_id,
      verdict_evidence,
      status,
      created_at,
      vehicle_plate
    ) VALUES (
      NEW.organization_id,
      NEW.id,
      COALESCE(NEW.set_id, ''),
      NEW.contract_id,
      NEW.payload -> 'verdict_evidence',
      'pending',
      NOW(),
      v_vehicle_plate
    )
    ON CONFLICT (ledger_entry_id) DO NOTHING;  -- INV-24: idempotent
  END IF;

  RETURN NEW;
END;
$$;
