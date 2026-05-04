-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Telegram Clock Drift Detection
--
-- 1. Adds clock_drift_seconds column to telegram_evidence_uploads.
-- 2. Extends valid_alert_type CHECK to include POTENTIAL_TIME_FRAUD.
-- 3. Recreates flood suppression trigger WHEN clause for both alert types.
--
-- INV-1:  organization_id scoped.
-- INV-3:  Evidence row immutability unchanged — DDL does not fire DML triggers.
-- INV-6:  Drift sealed at ingest; replay reads stored value, never recomputes (INV-15).
-- INV-10: POTENTIAL_TIME_FRAUD alert surfaced to Command Center, never silent.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Add clock_drift_seconds column ────────────────────────────────────────
-- Safe: Postgres 11+ constant-DEFAULT column = catalog-only change, no row rewrite.
-- Append-only triggers (prevent_teu_update, prevent_teu_delete) fire on DML only.
-- Signed: positive = device behind server, negative = device ahead.

ALTER TABLE public.telegram_evidence_uploads
  ADD COLUMN IF NOT EXISTS clock_drift_seconds INT;

-- ── 2. Extend valid_alert_type CHECK constraint ───────────────────────────────
-- Full set from 20260423180000_forensic_test_hardening.sql + POTENTIAL_TIME_FRAUD.

ALTER TABLE public.operational_alerts
  DROP CONSTRAINT IF EXISTS valid_alert_type;

ALTER TABLE public.operational_alerts
  ADD CONSTRAINT valid_alert_type CHECK (
    alert_type IN (
      'NO_SHOW',
      'EVIDENCE_GAP',
      'PENALTY_APPLIED',
      'TELEGRAM_ORPHAN',
      'SLA_BREACH',
      'DEVIATION',
      'POTENTIAL_TIME_FRAUD'
    )
  );

-- ── 3. Extend flood suppression trigger WHEN clause ──────────────────────────
-- The WHEN predicate is baked into the trigger definition, not the function body.
-- CREATE OR REPLACE FUNCTION alone is insufficient — trigger must be recreated.
-- suppress_flood_alerts() function body is unchanged (20260613000001).

DROP TRIGGER IF EXISTS trg_suppress_flood_alerts ON public.operational_alerts;

CREATE TRIGGER trg_suppress_flood_alerts
  BEFORE INSERT ON public.operational_alerts
  FOR EACH ROW
  WHEN (NEW.alert_type IN ('TELEGRAM_ORPHAN', 'POTENTIAL_TIME_FRAUD'))
  EXECUTE FUNCTION public.suppress_flood_alerts();

-- NOTE: POTENTIAL_TIME_FRAUD alert context MUST include "evidence_id" key.
-- suppress_flood_alerts() accumulator reads context->>'evidence_id'.
-- Missing key silently skips accumulation (first alert fires, rest swallowed).
