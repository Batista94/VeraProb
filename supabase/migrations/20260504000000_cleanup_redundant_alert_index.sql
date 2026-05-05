-- Migration: Cleanup redundant index on operational_alerts
--
-- Problem: idx_alerts_idempotency is a duplicate of unique_alert_per_event.
--          Each insert incurs double overhead for the same constraint check.
--
-- Solution: Drop the redundant index.
--
-- Invariants: INV-7 (Indices are operational metadata, dropping duplicates 
--             does not affect data integrity).

DROP INDEX IF EXISTS public.idx_alerts_idempotency;
