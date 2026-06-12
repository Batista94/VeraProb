BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_column('public', 'organizations', 'evidence_storage_enabled',
  'evidence_storage_enabled column added (5.2)');

SELECT col_type_is('public', 'organizations', 'evidence_storage_enabled', 'boolean',
  'evidence_storage_enabled is boolean');

SELECT col_not_null('public', 'organizations', 'evidence_storage_enabled',
  'evidence_storage_enabled is NOT NULL');

-- ── Default: opt-in (FALSE) — a new org cannot silently consume storage ───────
INSERT INTO public.organizations (id, name, cnpj)
VALUES ('00000000-0000-0000-0000-0000000e5201', 'Org ESF', '00000000000e51');

SELECT is(
  (SELECT evidence_storage_enabled FROM public.organizations
    WHERE id = '00000000-0000-0000-0000-0000000e5201'),
  FALSE,
  'evidence_storage_enabled defaults to FALSE (opt-in plan gate)');

-- ── Explicit TRUE persists (org on a paid storage plan) ──────────────────────
INSERT INTO public.organizations (id, name, cnpj, evidence_storage_enabled)
VALUES ('00000000-0000-0000-0000-0000000e5202', 'Org ESF-Paid', '00000000000e52', TRUE);

SELECT is(
  (SELECT evidence_storage_enabled FROM public.organizations
    WHERE id = '00000000-0000-0000-0000-0000000e5202'),
  TRUE,
  'evidence_storage_enabled persists TRUE for a contracted org');

-- ── The tenant can read its own org row (the flag rides existing grants) ──────
SELECT ok(
  has_table_privilege('authenticated', 'public.organizations', 'SELECT'),
  'authenticated may SELECT organizations (flag readable by the tenant)');

SELECT * FROM finish();
ROLLBACK;
