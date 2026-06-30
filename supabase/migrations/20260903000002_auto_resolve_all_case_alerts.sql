-- =============================================================================
-- Migration: Expand trigger to resolve ALL alert types on sanction terminal
--
-- Purpose:   Phase 1 (20260903000001) only resolved PENALTY_APPLIED and
--            DISPUTE_DEFENSE_SUBMITTED. AlertDerivationService also creates
--            NO_SHOW and EVIDENCE_GAP alerts for the same execution case
--            (same entity_id=set_id, contract_id). Those remained ACTIVE in
--            the Centro de Comando drawer after auditor action.
--
-- Fix:       CREATE OR REPLACE FUNCTION — expand WHERE to match ALL alert
--            types for the case key (entity_id + contract_id). The
--            DISPUTE_DEFENSE_SUBMITTED branch via context->>'queue_entry_id'
--            is preserved. Trigger trg_srq_resolve_alerts is unchanged.
--
-- INV-1:  organization_id filter on UPDATE WHERE — no cross-tenant resolve.
-- INV-22: Org A terminal action NEVER resolves Org B alerts.
-- Council: QA-Security ✅ (pure function replace, no schema change)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auto_resolve_alerts_on_sanction_terminal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status NOT IN ('applied', 'rejected', 'acknowledged')
     OR OLD.status IN ('applied', 'rejected', 'acknowledged') THEN
    RETURN NEW;
  END IF;

  UPDATE public.operational_alerts
  SET status          = 'RESOLVED',
      resolved_at_utc = NOW()
  WHERE organization_id = NEW.organization_id
    AND status = 'ACTIVE'
    AND (
      (entity_id   = NEW.set_id
       AND contract_id = NEW.contract_id)
      OR
      (alert_type = 'DISPUTE_DEFENSE_SUBMITTED'
       AND context->>'queue_entry_id' = NEW.id::text)
    );

  RETURN NEW;
END;
$$;
