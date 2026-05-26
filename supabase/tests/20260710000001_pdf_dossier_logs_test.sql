BEGIN;
SELECT plan(7);

-- Setup test roles
CREATE ROLE test_org_a NOLOGIN;
GRANT USAGE ON SCHEMA public TO test_org_a;
GRANT SELECT, INSERT ON public.pdf_dossier_logs TO test_org_a;

CREATE ROLE test_org_b NOLOGIN;
GRANT USAGE ON SCHEMA public TO test_org_b;
GRANT SELECT, INSERT ON public.pdf_dossier_logs TO test_org_b;

-- P1: Check columns
SELECT has_column('public', 'pdf_dossier_logs', 'id', 'id should exist');
SELECT has_column('public', 'pdf_dossier_logs', 'document_hash_sha256', 'hash should exist');

-- Seed organizations (using generic UUIDs)
DO $$
BEGIN
  -- Insert into pdf_dossier_logs as postgres to bypass RLS initially for setup if needed,
  -- but we'll just test the RLS policies directly.
END $$;

-- P4: Tenant Isolation (Read)
SET LOCAL ROLE test_org_a;
SET LOCAL request.jwt.claim.app_metadata = '{"org_id": "a0000000-0000-0000-0000-00000000000a"}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[0],
  'test_org_a initially sees 0 rows'
);

-- Insert a row for org_a
INSERT INTO public.pdf_dossier_logs (
  organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by
) VALUES (
  'a0000000-0000-0000-0000-00000000000a',
  'e0000000-0000-0000-0000-000000000001',
  'hash_a',
  'u0000000-0000-0000-0000-00000000000a'
);

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[1],
  'test_org_a sees 1 row after insert'
);

-- Switch to org_b
SET LOCAL ROLE test_org_b;
SET LOCAL request.jwt.claim.app_metadata = '{"org_id": "b0000000-0000-0000-0000-00000000000b"}';

SELECT results_eq(
  'SELECT count(*)::int FROM public.pdf_dossier_logs',
  ARRAY[0],
  'test_org_b sees 0 rows (isolated from org_a)'
);

-- P2: RLS violation on insert
SELECT throws_ok(
  $$ INSERT INTO public.pdf_dossier_logs (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by) VALUES ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'hash_b', 'u0000000-0000-0000-0000-00000000000b') $$,
  'new row violates row-level security policy for table "pdf_dossier_logs"',
  'Cannot insert record for another organization'
);

-- P3: NOT NULL on generated_by
SET LOCAL ROLE test_org_a;
SET LOCAL request.jwt.claim.app_metadata = '{"org_id": "a0000000-0000-0000-0000-00000000000a"}';
SELECT throws_ok(
  $$ INSERT INTO public.pdf_dossier_logs
     (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by)
     VALUES ('a0000000-0000-0000-0000-00000000000a',
             'e0000000-0000-0000-0000-000000000002',
             'hash_c', NULL) $$,
  'null value in column "generated_by" of relation "pdf_dossier_logs" violates not-null constraint',
  'generated_by cannot be null'
);

SELECT * FROM finish();

ROLLBACK;
