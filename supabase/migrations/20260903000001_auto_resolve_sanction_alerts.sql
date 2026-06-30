-- =============================================================================
-- Migration: Auto-resolve operational alerts on sanction terminal verdict
--
-- Purpose:   AFTER UPDATE trigger on sanction_review_queue that atomically
--            resolves matching operational_alerts (PENALTY_APPLIED and
--            DISPUTE_DEFENSE_SUBMITTED) when status enters a terminal state.
--
-- Root cause: Auditor actions (approve, reject, resolveDispute,
--             acknowledgeInternal) flip queue status to terminal but leave
--             ACTIVE alerts in the Centro de Comando drawer indefinitely.
--             Zero code among the 7 action handlers resolves alerts.
--
-- Fix:       DB trigger (ponytail — one place, zero Dart changes). Resolves
--            alerts in the same transaction as the status flip.
--            activeAlertsStreamProvider filters status='ACTIVE' via Realtime;
--            the resolved alert auto-disappears from the drawer.
--
-- Matching:
--   PENALTY_APPLIED:            entity_id = NEW.set_id
--                               AND contract_id = NEW.contract_id
--   DISPUTE_DEFENSE_SUBMITTED:  context->>'queue_entry_id' = NEW.id::text
--
-- Guard: fires only on FIRST entry into terminal state.
--        No-op when OLD.status is already terminal (applied→acknowledged,
--        idempotent re-fires) — prevents double-resolving on dead paths.
--
-- Terminal states: 'applied', 'rejected', 'acknowledged'
-- Non-terminal (no-op): 'pending', 'disputed', 'pending_peer_review'
--
-- INV-1:  Does not touch immutable fields (organization_id, ledger_entry_id,
--         set_id, contract_id, verdict_evidence, created_at).
-- INV-22: organization_id filter on WHERE clause — no cross-tenant resolve.
-- Council: QA-Security ✅ (trigger-only, no Dart changes, atomic with flip)
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
      (alert_type = 'PENALTY_APPLIED'
        AND entity_id   = NEW.set_id
        AND contract_id = NEW.contract_id)
      OR
      (alert_type = 'DISPUTE_DEFENSE_SUBMITTED'
        AND context->>'queue_entry_id' = NEW.id::text)
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_srq_resolve_alerts ON public.sanction_review_queue;
CREATE TRIGGER trg_srq_resolve_alerts
  AFTER UPDATE ON public.sanction_review_queue
  FOR EACH ROW EXECUTE FUNCTION public.auto_resolve_alerts_on_sanction_terminal();
