BEGIN;
SELECT plan(7);

-- Corrective migration 20260714000001 replaces the RLS policy on
-- pdf_dossier_logs to fix the JWT claim path from the broken
-- auth.jwt() ->> 'organization_id' to the canonical
-- auth.jwt() -> 'app_metadata' ->> 'org_id'.

GRANT SELECT, INSERT ON public.pdf_dossier_logs TO authenticated;

-- ── TC1: Baseline — org_a sees 0 rows initially ─────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[0],
  'TC1/INV-2: org_a initially sees 0 rows'
);

-- ── TC2: org_a can insert and see own row ────────────────────────────────

INSERT INTO public.pdf_dossier_logs (
  organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by
) VALUES (
  'a0000000-0000-0000-0000-00000000000a',
  'e0000000-0000-0000-0000-000000000010',
  'sha256_corrective_test_a',
  '00000000-0000-0000-0000-000000000002'
);

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[1],
  'TC2/INV-2: org_a sees 1 row after insert (JWT path works)'
);

-- ── TC3: org_b cannot see org_a rows (tenant isolation) ──────────────────

SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"b0000000-0000-0000-0000-00000000000b"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[0],
  'TC3/INV-22: org_b sees 0 rows (isolated from org_a)'
);

-- ── TC4: org_b cannot insert row for org_a ───────────────────────────────

SELECT throws_ok(
  $$ INSERT INTO public.pdf_dossier_logs (
       organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by
     ) VALUES (
       'a0000000-0000-0000-0000-00000000000a',
       'e0000000-0000-0000-0000-000000000020',
       'sha256_crossorg_attempt',
       '00000000-0000-0000-0000-000000000003'
     ) $$,
  'new row violates row-level security policy for table "pdf_dossier_logs"',
  'TC4/INV-22: Cross-tenant insert blocked by RLS WITH CHECK'
);

-- ── TC5: org_b can insert and see its own row ────────────────────────────

INSERT INTO public.pdf_dossier_logs (
  organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by
) VALUES (
  'b0000000-0000-0000-0000-00000000000b',
  'e0000000-0000-0000-0000-000000000030',
  'sha256_corrective_test_b',
  '00000000-0000-0000-0000-000000000003'
);

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[1],
  'TC5/INV-2: org_b sees only its own 1 row'
);

-- ── TC6: Switch back to org_a — still sees only 1 row ────────────────────

SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"a0000000-0000-0000-0000-00000000000a"}}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[1],
  'TC6/INV-22: org_a still sees exactly 1 row (own data only)'
);

-- ── TC7: Verify hash column integrity ────────────────────────────────────

SELECT results_eq(
  $$ SELECT document_hash_sha256 FROM public.pdf_dossier_logs
     WHERE organization_id = 'a0000000-0000-0000-0000-00000000000a' $$,
  ARRAY['sha256_corrective_test_a'::text],
  'TC7/INV-9: Hash stored correctly for org_a'
);

SELECT * FROM finish();
ROLLBACK;
