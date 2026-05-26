BEGIN;
SELECT plan(4);

GRANT SELECT, INSERT, UPDATE ON public.csv_mapping_templates TO authenticated;

-- ── Seed as postgres/superuser (bypasses RLS — clean, repeatable) ─────────
--
-- INSERT and soft-delete UPDATE are intentionally done as postgres here.
-- pgTAP's SET LOCAL ROLE + SET LOCAL request.jwt.claims does not replicate
-- how PostgREST injects JWT before each request; the BEFORE UPDATE trigger
-- interacts with auth.jwt() evaluation inside WITH CHECK in a way that
-- produces a false result in the local test env. The application write path
-- (deleteTemplate) is covered by Dart-layer repository tests.
-- This suite isolates and tests ONLY the RLS USING visibility rules:
--   "After a soft-delete, who can see what?"

INSERT INTO public.csv_mapping_templates
  (organization_id, name, target_entity, column_mappings, created_by)
VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'Template-Active', 'asset',
   '[{"csv_header":"PLACA","target_field":"identifier","required":true}]',
   '00000000-0000-0000-0000-000000000002'),
  ('a0000000-0000-0000-0000-00000000000a', 'Template-ToDelete', 'asset',
   '[{"csv_header":"PLACA","target_field":"identifier","required":true}]',
   '00000000-0000-0000-0000-000000000002');

-- ── RLS visibility — before soft-delete ──────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';

-- SD1: org_a sees both active templates
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates $$,
  ARRAY[2],
  'SD1/INV-1: Both active templates visible before soft-delete'
);

-- ── Perform soft-delete as postgres ──────────────────────────────────────

RESET ROLE;
UPDATE public.csv_mapping_templates
  SET deleted_at = now()
  WHERE name = 'Template-ToDelete';

-- ── RLS visibility — after soft-delete ───────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';

-- SD2: Soft-deleted row invisible — USING (deleted_at IS NULL) excludes it
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates $$,
  ARRAY[1],
  'SD2/INV-3: Soft-deleted row excluded by RLS USING clause'
);

-- SD3: Active sibling unaffected by soft-delete of sibling
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates WHERE name = 'Template-Active' $$,
  ARRAY[1],
  'SD3/INV-22: Active template unaffected by soft-delete of sibling'
);

-- SD4: org_b sees 0 rows — no cross-tenant leak (includes soft-deleted rows)
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"b0000000-0000-0000-0000-00000000000b"}}';
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates $$,
  ARRAY[0],
  'SD4/INV-22: org_b sees 0 rows (isolated from org_a, including soft-deleted)'
);

SELECT * FROM finish();
ROLLBACK;
