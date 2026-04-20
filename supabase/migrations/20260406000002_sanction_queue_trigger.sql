-- Suppress DROP TRIGGER IF EXISTS NOTICE (trigger doesn't exist on fresh reset).
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Auto-populate sanction_review_queue from SANCTION_RECOMMENDED
--
-- Trigger fires AFTER INSERT on sla_audit_ledger_v2 where type = 'SANCTION_RECOMMENDED'.
-- This decouples the engine from direct queue writes — the DB enforces the
-- Human-in-the-Loop contract automatically.
--
-- INV-24: ON CONFLICT DO NOTHING prevents duplicate queue entries.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auto_enqueue_sanction_recommended()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.type = 'SANCTION_RECOMMENDED' THEN
    INSERT INTO public.sanction_review_queue (
      organization_id,
      ledger_entry_id,
      set_id,
      contract_id,
      verdict_evidence,
      status,
      created_at
    ) VALUES (
      NEW.organization_id,
      NEW.id,
      COALESCE(NEW.set_id, ''),
      NEW.contract_id,
      NEW.payload -> 'verdict_evidence',
      'pending',
      NOW()
    )
    ON CONFLICT (ledger_entry_id) DO NOTHING;  -- INV-24: idempotent
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_enqueue_sanction
  ON public.sla_audit_ledger_v2;
CREATE TRIGGER trg_auto_enqueue_sanction
  AFTER INSERT ON public.sla_audit_ledger_v2
  FOR EACH ROW EXECUTE FUNCTION public.auto_enqueue_sanction_recommended();
