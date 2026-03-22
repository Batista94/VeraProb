-- Suppress DROP/IF EXISTS NOTICEs on fresh reset.
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Add financial_ceiling_cents to contracts
--
-- financialCeiling is the contractual maximum penalty cap (INV-2: BIGINT cents).
-- Optional — NULL means no ceiling defined.
-- =============================================================================

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS financial_ceiling_cents BIGINT;
