BEGIN;
SELECT plan(7);

GRANT SELECT, INSERT, UPDATE ON public.csv_mapping_templates TO authenticated;

-- ── TC1: Table exists with expected columns ──────────────────────────────

SELECT has_column('public', 'csv_mapping_templates', 'id', 'TC1a: id column exists');
SELECT has_column('public', 'csv_mapping_templates', 'organization_id', 'TC1b: organization_id column exists');
SELECT has_column('public', 'csv_mapping_templates', 'column_mappings', 'TC1c: column_mappings JSONB exists');

-- ── TC2: Tenant isolation — org_a sees own rows only ─────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.csv_mapping_templates',
  ARRAY[0],
  'TC2/INV-1: org_a initially sees 0 rows'
);

-- ── TC3: org_a can insert own template ───────────────────────────────────

INSERT INTO public.csv_mapping_templates
  (organization_id, name, target_entity, column_mappings, created_by)
VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'Test-Template-A', 'asset',
   '[{"csv_header":"PLACA","target_field":"identifier","required":true}]',
   '00000000-0000-0000-0000-000000000002');

SELECT results_eq(
  'SELECT count(*)::int FROM public.csv_mapping_templates',
  ARRAY[1],
  'TC3/INV-2: org_a sees 1 row after insert (RLS JWT path works)'
);

-- ── TC4: org_b cannot see org_a data ─────────────────────────────────────

SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"b0000000-0000-0000-0000-00000000000b"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.csv_mapping_templates',
  ARRAY[0],
  'TC4/INV-22: org_b sees 0 rows (isolated from org_a)'
);

-- ── TC5: org_b cannot insert row for org_a ───────────────────────────────

SELECT throws_ok(
  $$ INSERT INTO public.csv_mapping_templates
       (organization_id, name, target_entity, column_mappings, created_by)
     VALUES
       ('a0000000-0000-0000-0000-00000000000a', 'Attack-Template', 'asset',
        '[{"csv_header":"X","target_field":"identifier"}]',
        '00000000-0000-0000-0000-000000000003') $$,
  'new row violates row-level security policy for table "csv_mapping_templates"',
  'TC5/INV-22: Cross-tenant insert blocked by RLS WITH CHECK'
);

SELECT * FROM finish();
ROLLBACK;
