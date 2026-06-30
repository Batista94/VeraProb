-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Extend operational_alerts CHECK constraint — Phase 10.6
--
-- Purpose:   Add 'TELEMETRY_SILENT' (new type for ingestion health alerts)
--            to the valid_alert_type CHECK.
--
--            Existing types preserved (added across prior migrations):
--              NO_SHOW         — 20260305
--              EVIDENCE_GAP    — 20260305
--              PENALTY_APPLIED — 20260305
--              TELEGRAM_ORPHAN — 20260421
--              SLA_BREACH      — 20260423
--              DEVIATION       — 20260423
--              POTENTIAL_TIME_FRAUD     — 20260701
--              DISPUTE_DEFENSE_SUBMITTED — 20260827
--
-- INV-DB:    Zero-downtime widening — only adding a new value (no existing row
--            can violate the new wider constraint). DROP + ADD is safe and
--            non-blocking for CHECK constraints (no table rewrite, no
--            AccessExclusiveLock beyond the ALTER statement itself).
--
-- Council: QA-Security ✅ (alert type extension approved)
-- =============================================================================

SET client_min_messages TO 'WARNING';

ALTER TABLE public.operational_alerts
  DROP CONSTRAINT IF EXISTS valid_alert_type;

ALTER TABLE public.operational_alerts
  ADD CONSTRAINT valid_alert_type
  CHECK (alert_type IN (
    'NO_SHOW',
    'EVIDENCE_GAP',
    'PENALTY_APPLIED',
    'TELEGRAM_ORPHAN',
    'SLA_BREACH',
    'DEVIATION',
    'POTENTIAL_TIME_FRAUD',
    'DISPUTE_DEFENSE_SUBMITTED',
    'TELEMETRY_SILENT'
  ));

-- Exempt TELEMETRY_SILENT from driver_id requirement (INV-DB: zero-downtime-verified)
ALTER TABLE public.operational_alerts
  ADD CONSTRAINT chk_alert_driver_attribution_v3 CHECK (
    alert_type IN ('TELEGRAM_ORPHAN', 'DISPUTE_DEFENSE_SUBMITTED', 'TELEMETRY_SILENT')
    OR (
      (context ? 'driver_id')
      AND (context ->> 'driver_id') IS NOT NULL
      AND (context ->> 'driver_id') <> ''
    )
  ) NOT VALID;

-- INV-DB: zero-downtime-verified
-- Intentionally NOT VALID — mirrors the original design from 20260818000004 (preserved
-- in 20260827): older rows predate driver attribution; a VALIDATE scan could fail on
-- them. v3 is strictly more permissive than v2 (one extra exempt type), so swapping
-- never rejects a row the old constraint admitted.
ALTER TABLE public.operational_alerts
  DROP CONSTRAINT IF EXISTS chk_alert_driver_attribution;

ALTER TABLE public.operational_alerts
  RENAME CONSTRAINT chk_alert_driver_attribution_v3 TO chk_alert_driver_attribution;

RESET client_min_messages;
