SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Driver attribution guard on operational_alerts (INV-18)
--
-- Prevents unattributed alerts from entering storage for all driver-bound
-- alert types. TELEGRAM_ORPHAN is exempt: orphan = message not yet linked
-- to any driver by definition.
--
-- INV-18: Zero-Trust telemetry — unidentified origin must be quarantined,
--         not surfaced in the Command Center UI.
-- INV-DB: NOT VALID — no table scan on existing rows; only guards new inserts.
-- =============================================================================

ALTER TABLE public.operational_alerts
  ADD CONSTRAINT chk_alert_driver_attribution
  CHECK (
    alert_type = 'TELEGRAM_ORPHAN'
    OR (
      (context ? 'driver_id')
      AND (context ->> 'driver_id') IS NOT NULL
      AND (context ->> 'driver_id') <> ''
    )
  ) NOT VALID;

COMMENT ON CONSTRAINT chk_alert_driver_attribution ON public.operational_alerts IS
  'INV-18: All driver-bound alert types must carry a non-empty driver_id in context. '
  'TELEGRAM_ORPHAN is exempt (unlinked by definition). NOT VALID = no scan on history.';
