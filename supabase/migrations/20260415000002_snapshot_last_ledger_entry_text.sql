-- =============================================================================
-- Migration: 20260415000002 — Add contractual_financial_snapshot.last_ledger_entry_uuid
--                             (TEXT) to support v2 ledger UUIDs (INV-DB)
--
-- Problem:
--   sla_audit_ledger_v2 uses UUID primary keys, but the existing
--   last_ledger_entry_id was defined as BIGINT.
--
-- Fix:
--   Add a new column 'last_ledger_entry_uuid' (TEXT) to store UUID strings
--   while maintaining append-only schema invariants.
-- =============================================================================

-- Add new column for UUID-based ledger entries
ALTER TABLE public.contractual_financial_snapshot
  ADD COLUMN IF NOT EXISTS last_ledger_entry_uuid TEXT;

-- NOTE: existing last_ledger_entry_id (BIGINT) is kept for backward compatibility
-- but will be empty for all v2 ledger entries.
