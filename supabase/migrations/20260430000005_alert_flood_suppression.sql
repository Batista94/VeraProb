-- Bloco 5 Anti-Flood: Smart Debounce for operational_alerts
--
-- Problem: Each orphan photo generates a separate TELEGRAM_ORPHAN alert because
--          fireOrphanAlert() uses a unique correlationId per request, bypassing
--          the UNIQUE(triggering_event_id, alert_type) constraint.
--          10 orphan photos in 30s = 10 CRITICAL alerts = Alert Fatigue.
--
-- Solution: BEFORE INSERT trigger that silently suppresses duplicate alerts
--           for the same (org, entity, alert_type) within a 15-minute window.
--           Evidence in telegram_evidence_uploads is NEVER affected (INV-3).
--
-- Invariants: INV-3 (Ledger immutability — alerts are operational, not evidence)
--             INV-1 (organization_id scoped)
--             INV-16 (lightweight trigger, index-backed, no extra connections)

-- ── 1. Dedicated index for the trigger's EXISTS query ────────────────────────
-- None of the existing indexes cover (organization_id, entity_id, alert_type, status, triggered_at_utc).
-- Partial index: only ACTIVE alerts need checking; resolved/acknowledged are irrelevant.

CREATE INDEX IF NOT EXISTS idx_alerts_flood_suppression
  ON public.operational_alerts (organization_id, entity_id, alert_type, triggered_at_utc DESC)
  WHERE status = 'ACTIVE';

-- ── 2. Suppression function ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.suppress_flood_alerts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.operational_alerts
    WHERE organization_id = NEW.organization_id
      AND entity_id       = NEW.entity_id
      AND alert_type      = NEW.alert_type
      AND status          = 'ACTIVE'
      AND triggered_at_utc > NOW() - INTERVAL '15 minutes'
    LIMIT 1
  ) THEN
    -- Suppress: evidence is already sealed in telegram_evidence_uploads.
    -- This only prevents a redundant operational notification.
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- ── 3. Trigger (BEFORE INSERT, filtered to TELEGRAM_ORPHAN only) ─────────────

CREATE TRIGGER trg_suppress_flood_alerts
  BEFORE INSERT ON public.operational_alerts
  FOR EACH ROW
  WHEN (NEW.alert_type = 'TELEGRAM_ORPHAN')
  EXECUTE FUNCTION public.suppress_flood_alerts();
