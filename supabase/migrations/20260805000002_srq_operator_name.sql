SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Add operator_name to sanction_review_queue (Asset/Operator — INV-14)
--
-- Mirrors the vehicle_plate denormalization (20260610000001). The enqueue trigger
-- resolves the operator (driver) name from the authoritative registry via the
-- bound execution, so the auditor sees WHO drove the asset that produced the
-- evidence — without runtime JOINs on the hot read path.
--
-- INV-1:  operator_name is forensic context — immutable once set (guard trigger).
-- INV-14: Operator identity complements the Asset (vehicle_plate).
-- INV-18: Zero-Trust — payload identity is only a fallback for executions with no
--         authoritative binding (dev simulation). The registry join always wins.
-- INV-DB: additive nullable column — zero-downtime.
-- =============================================================================

-- ── A: Add column ─────────────────────────────────────────────────────────────
ALTER TABLE public.sanction_review_queue
  ADD COLUMN IF NOT EXISTS operator_name TEXT NULL;

-- ── B: Extend the immutability guard to cover operator_name (INV-1) ───────────
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
     NEW.vehicle_plate     IS DISTINCT FROM OLD.vehicle_plate     OR
     NEW.operator_name     IS DISTINCT FROM OLD.operator_name
  THEN
    RAISE EXCEPTION
      'sanction_review_queue: immutable field mutation attempted (INV-1). id: %', OLD.id
    USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END;
$$;

-- ── C: Enqueue trigger resolves BOTH asset (plate) and operator (name) ─────────
CREATE OR REPLACE FUNCTION public.auto_enqueue_sanction_recommended()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_vehicle_plate TEXT;
  v_operator_name TEXT;
BEGIN
  IF NEW.type = 'SANCTION_RECOMMENDED' THEN
    -- Authoritative resolution via the bound execution → registry (org-scoped).
    SELECT v.plate, d.full_name
      INTO v_vehicle_plate, v_operator_name
    FROM public.execution_states es
    LEFT JOIN public.vehicles v
      ON v.id::text = es.bound_vehicle_id
     AND v.organization_id = NEW.organization_id
    LEFT JOIN public.drivers d
      ON d.id = es.bound_operator_id
     AND d.organization_id = NEW.organization_id
    WHERE es.set_id = COALESCE(NEW.set_id, '')
      AND es.organization_id = NEW.organization_id
    LIMIT 1;

    -- INV-18 Zero-Trust fallback: only used when no authoritative binding exists
    -- (e.g. dev simulation). Real engine verdicts always resolve from the join.
    v_vehicle_plate := COALESCE(v_vehicle_plate, NEW.payload ->> 'vehicle_plate');
    v_operator_name := COALESCE(v_operator_name, NEW.payload ->> 'operator_name');

    INSERT INTO public.sanction_review_queue (
      organization_id,
      ledger_entry_id,
      set_id,
      contract_id,
      verdict_evidence,
      status,
      created_at,
      vehicle_plate,
      operator_name
    ) VALUES (
      NEW.organization_id,
      NEW.id,
      COALESCE(NEW.set_id, ''),
      NEW.contract_id,
      NEW.payload -> 'verdict_evidence',
      'pending',
      NOW(),
      v_vehicle_plate,
      v_operator_name
    )
    ON CONFLICT (ledger_entry_id) DO NOTHING;  -- INV-24: idempotent
  END IF;

  RETURN NEW;
END;
$$;
