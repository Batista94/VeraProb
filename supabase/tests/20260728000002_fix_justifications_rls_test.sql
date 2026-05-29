BEGIN;
SELECT plan(6);

-- Verify that RLS on contractor_justifications uses canonical JWT claims:
-- auth.jwt() -> 'app_metadata' ->> 'org_id'

-- ── Setup: Grant permissions to authenticated role for test scope ───────────────────
GRANT SELECT, INSERT, UPDATE ON public.contractor_justifications TO authenticated;

-- ── TC1: Baseline — org_a sees 0 rows initially ─────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000001","role":"TENANT_ADMIN"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.contractor_justifications',
  ARRAY[0],
  'TC1/INV-22: Org A initially sees 0 justifications'
);

-- ── TC2: org_a can insert and see own row ────────────────────────────────
INSERT INTO public.contractor_justifications (
  organization_id, contract_id, set_id, category, description, status
) VALUES (
  '00000000-0000-0000-0000-000000000001',
  'contract-test-a',
  'set-test-a',
  'MECHANICAL',
  'This is a valid test description that meets length check requirements',
  'PENDING'
);

SELECT results_eq(
  'SELECT count(*)::int FROM public.contractor_justifications',
  ARRAY[1],
  'TC2/INV-22: Org A can insert and see its own justification'
);

-- ── TC3: org_b cannot see org_a rows (tenant isolation) ──────────────────
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000002","role":"TENANT_ADMIN"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.contractor_justifications',
  ARRAY[0],
  'TC3/INV-22: Org B sees 0 rows (isolated from Org A)'
);

-- ── TC4: org_b cannot insert row for org_a ───────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.contractor_justifications (
       organization_id, contract_id, set_id, category, description, status
     ) VALUES (
       '00000000-0000-0000-0000-000000000001',
       'contract-test-a',
       'set-test-a',
       'FORCE_MAJEURE',
       'Another valid description for test reasons that is long enough',
       'PENDING'
     ) $$,
  'new row violates row-level security policy for table "contractor_justifications"',
  'TC4/INV-22: Cross-tenant insert blocked by RLS WITH CHECK'
);

-- ── TC5: org_b can insert and see its own row ────────────────────────────
INSERT INTO public.contractor_justifications (
  organization_id, contract_id, set_id, category, description, status
) VALUES (
  '00000000-0000-0000-0000-000000000002',
  'contract-test-b',
  'set-test-b',
  'TRAFFIC',
  'Valid traffic incident description for testing contractor justification',
  'PENDING'
);

SELECT results_eq(
  'SELECT count(*)::int FROM public.contractor_justifications',
  ARRAY[1],
  'TC5/INV-22: Org B sees only its own 1 row'
);

-- ── TC6: Switch back to org_a — still sees only 1 row ────────────────────
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000001","role":"TENANT_ADMIN"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.contractor_justifications',
  ARRAY[1],
  'TC6/INV-22: Org A still sees exactly its own 1 row'
);

SELECT * FROM finish();
ROLLBACK;
