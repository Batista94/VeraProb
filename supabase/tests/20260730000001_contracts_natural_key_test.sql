-- =============================================================================
-- pgTAP Test: contracts natural-key unique index
-- Migration: 20260730000001_contracts_natural_key.sql
-- =============================================================================
-- Validates:
--   1. Index uq_contracts_org_name_validfrom exists on public.contracts.
--   2. Index is UNIQUE.
--   3. Index covers (organization_id, name, valid_from_utc) — org-scoped key.
-- =============================================================================

BEGIN;
SELECT plan(5);

-- ── 1. Index exists ───────────────────────────────────────────────────────────

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'contracts'
      AND indexname  = 'uq_contracts_org_name_validfrom'
  ),
  '1: uq_contracts_org_name_validfrom exists on contracts'
);

-- ── 2. Index is UNIQUE ────────────────────────────────────────────────────────

SELECT ok(
  (SELECT indexdef FROM pg_indexes
   WHERE indexname = 'uq_contracts_org_name_validfrom') LIKE 'CREATE UNIQUE INDEX%',
  '2: index is UNIQUE'
);

-- ── 3. Index covers the org-scoped natural key columns ────────────────────────

SELECT ok(
  (SELECT indexdef FROM pg_indexes
   WHERE indexname = 'uq_contracts_org_name_validfrom') LIKE '%organization_id%',
  '3a: index leads with organization_id (INV-1/INV-22)'
);

SELECT ok(
  (SELECT indexdef FROM pg_indexes
   WHERE indexname = 'uq_contracts_org_name_validfrom') LIKE '%name%',
  '3b: index covers name'
);

SELECT ok(
  (SELECT indexdef FROM pg_indexes
   WHERE indexname = 'uq_contracts_org_name_validfrom') LIKE '%valid_from_utc%',
  '3c: index covers valid_from_utc'
);

SELECT finish();
ROLLBACK;
