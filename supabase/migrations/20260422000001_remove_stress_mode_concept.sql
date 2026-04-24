-- =============================================================================
-- Migration: Remove Stress Mode Concept
-- Date: 2026-04-22
--
-- CONTEXT:
--   The "Stress Mode" was a dev-only concept implemented entirely at the
--   Flutter application layer (stressScenarioProvider / dart-define STRESS_MODE).
--   It had NO corresponding database column or trigger.
--
-- CHANGE:
--   This migration is a FORENSIC TOMBSTONE: it documents the removal of the
--   concept for audit trail completeness (INV-7).
--
-- INV-7 COMPLIANCE:
--   No existing records are deleted or mutated. This migration is purely
--   additive (a comment-only no-op at the DDL level) — fully respecting the
--   Append-Only invariant.
--
-- WS-4 IMPACT:
--   The find_execution_for_telegram RPC retains its fixed forensic windows:
--     [message_ts - 10min, message_ts + 4h]
--   These windows are ALWAYS applied with maximum rigor. There is no
--   "relaxed mode" or stress-mode exception path anymore.
--
-- FLOOD SUPPRESSION:
--   trg_suppress_flood_alerts continues to operate as the sole deduplication
--   mechanism for mass-submission scenarios (INV-7, INV-15).
-- =============================================================================

-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs.
SET client_min_messages TO 'WARNING';

-- Verify: confirm no is_stress_mode column exists on any table (defensive assertion).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE column_name = 'is_stress_mode'
      AND table_schema = 'public'
  ) THEN
    RAISE EXCEPTION
      'Unexpected is_stress_mode column found. Manual review required before proceeding.'
    USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

-- No further DDL required. The stress-mode concept existed only in the
-- application layer and has been removed from Flutter source code.
-- This migration serves as the immutable audit record of that removal.
