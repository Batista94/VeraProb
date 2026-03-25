-- =============================================================================
-- Migration: 20260415000002 — Change contractual_financial_snapshot.last_ledger_entry_id
--                             from BIGINT (v1 ledger FK) to TEXT (v2 ledger UUID)
--
-- Problem:
--   sla_audit_ledger_v2 uses UUID primary keys, but last_ledger_entry_id was
--   defined as BIGINT with a foreign key to sla_audit_ledger (v1, BIGINT IDs).
--   When the snapshot generator calls ledgerRepo.getLastEntryId() it receives
--   a UUID string. int.tryParse(uuid) returns null, so null is persisted and
--   snap.lastLedgerEntryId is always null — breaking the E2E Stage 4 assertion.
--
-- Fix:
--   Drop the FK constraint and change the column type to TEXT so UUID strings
--   from sla_audit_ledger_v2 are stored as-is. Existing null rows are unaffected.
-- =============================================================================

-- Drop the FK constraint referencing sla_audit_ledger(id) (v1, BIGINT)
ALTER TABLE public.contractual_financial_snapshot
  DROP CONSTRAINT IF EXISTS contractual_financial_snapshot_last_ledger_entry_id_fkey;

-- Change column type from BIGINT to TEXT (no data loss — existing rows are null
-- because the FK previously prevented UUID values from being stored)
ALTER TABLE public.contractual_financial_snapshot
  ALTER COLUMN last_ledger_entry_id TYPE TEXT USING last_ledger_entry_id::text;
