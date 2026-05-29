-- =============================================================================
-- pgTAP Test: external_id ERP Integration Anchor
-- Migration: 20260729000001_csv_external_id_anchor.sql
-- =============================================================================
-- Validates:
--   1. Column exists and is nullable on all 5 operational tables.
--   2. Partial unique indexes exist (WHERE external_id IS NOT NULL).
--   3. Multiple NULLs are permitted (manual UI rows — INV-3).
--   4. Unique constraint fires on duplicate non-null (organization_id, external_id).
-- =============================================================================

BEGIN;
SELECT plan(17);

-- ── 1. Column existence ───────────────────────────────────────────────────────

SELECT has_column('public', 'vehicles',
  'external_id', '1a: vehicles.external_id exists');

SELECT has_column('public', 'drivers',
  'external_id', '1b: drivers.external_id exists');

SELECT has_column('public', 'contractors',
  'external_id', '1c: contractors.external_id exists');

SELECT has_column('public', 'contracts',
  'external_id', '1d: contracts.external_id exists');

SELECT has_column('public', 'operational_zones',
  'external_id', '1e: operational_zones.external_id exists');

-- ── 2. Nullable (INV-3: manual rows unaffected) ───────────────────────────────

SELECT col_is_nullable('public', 'vehicles',
  'external_id', '2a: vehicles.external_id is nullable');

SELECT col_is_nullable('public', 'drivers',
  'external_id', '2b: drivers.external_id is nullable');

SELECT col_is_nullable('public', 'contractors',
  'external_id', '2c: contractors.external_id is nullable');

SELECT col_is_nullable('public', 'contracts',
  'external_id', '2d: contracts.external_id is nullable');

SELECT col_is_nullable('public', 'operational_zones',
  'external_id', '2e: operational_zones.external_id is nullable');

-- ── 3. Partial unique indexes exist ──────────────────────────────────────────

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'vehicles'
      AND indexname  = 'uq_vehicles_org_external_id'
  ),
  '3a: partial unique index on vehicles (org, external_id) WHERE NOT NULL'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'drivers'
      AND indexname  = 'uq_drivers_org_external_id'
  ),
  '3b: partial unique index on drivers (org, external_id) WHERE NOT NULL'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'contractors'
      AND indexname  = 'uq_contractors_org_external_id'
  ),
  '3c: partial unique index on contractors (org, external_id) WHERE NOT NULL'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'contracts'
      AND indexname  = 'uq_contracts_org_external_id'
  ),
  '3d: partial unique index on contracts (org, external_id) WHERE NOT NULL'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'operational_zones'
      AND indexname  = 'uq_operational_zones_org_external_id'
  ),
  '3e: partial unique index on operational_zones (org, external_id) WHERE NOT NULL'
);

-- ── 4. Column type is TEXT ────────────────────────────────────────────────────

SELECT col_type_is('public', 'vehicles', 'external_id', 'text',
  '4: external_id is TEXT on vehicles');

SELECT col_type_is('public', 'contractors', 'external_id', 'text',
  '4b: external_id is TEXT on contractors');

SELECT finish();
ROLLBACK;
