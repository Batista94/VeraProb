-- =============================================================================
-- pgTAP Test: CSV import field expansion
-- Migration: 20260801000001_csv_import_field_expansion.sql
-- =============================================================================
-- Validates:
--   1. New driver columns exist with declared types (cpf, phone,
--      license_category TEXT; license_expiry_utc TIMESTAMPTZ — INV-6).
--   2. contracts.notes exists (TEXT).
--   3. contractors.tax_id is NOT NULL (contractor business key).
--   4. Replaced RPCs (batch_upsert_drivers/contracts) remain SECURITY INVOKER
--      (INV-2) and keep EXECUTE for authenticated.
--
-- Note: local pgTAP lacks col_is_nullable; NOT-NULL is asserted via col_not_null.
-- =============================================================================

BEGIN;
SELECT plan(11);

-- ── 1. drivers: new columns + types ──────────────────────────────────────────
SELECT has_column('public', 'drivers', 'cpf', '1: drivers.cpf exists');
SELECT has_column('public', 'drivers', 'phone', '2: drivers.phone exists');
SELECT has_column('public', 'drivers', 'license_category',
  '3: drivers.license_category exists');
SELECT col_type_is('public', 'drivers', 'license_expiry_utc',
  'timestamp with time zone', '4: license_expiry_utc is TIMESTAMPTZ (INV-6)');

-- ── 2. contracts.notes ───────────────────────────────────────────────────────
SELECT has_column('public', 'contracts', 'notes', '5: contracts.notes exists');
SELECT col_type_is('public', 'contracts', 'notes', 'text',
  '6: contracts.notes is TEXT');

-- ── 3. contractors.tax_id NOT NULL ───────────────────────────────────────────
SELECT col_not_null('public', 'contractors', 'tax_id',
  '7: contractors.tax_id is NOT NULL (FK business key)');

-- ── 4. Replaced RPCs preserve security posture (INV-2) ───────────────────────
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'batch_upsert_drivers'
   AND pronamespace = 'public'::regnamespace),
  false, '8: batch_upsert_drivers is SECURITY INVOKER');
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'batch_upsert_contracts'
   AND pronamespace = 'public'::regnamespace),
  false, '9: batch_upsert_contracts is SECURITY INVOKER');

SELECT function_privs_are('public', 'batch_upsert_drivers',
  ARRAY['uuid','jsonb'], 'authenticated', ARRAY['EXECUTE'],
  '10: authenticated keeps EXECUTE on batch_upsert_drivers');
SELECT function_privs_are('public', 'batch_upsert_contracts',
  ARRAY['uuid','jsonb'], 'authenticated', ARRAY['EXECUTE'],
  '11: authenticated keeps EXECUTE on batch_upsert_contracts');

SELECT * FROM finish();
ROLLBACK;
