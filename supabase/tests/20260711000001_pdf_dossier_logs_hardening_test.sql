BEGIN;
SELECT plan(4);

-- Ensure authenticated role has permissions (just in case default privileges differ)
GRANT SELECT, INSERT ON public.pdf_dossier_logs TO authenticated;

-- H1 & H2: UPDATE and DELETE are blocked for authenticated role (INV-3)
-- Set role to authenticated and configure JWT claims for org A
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role": "authenticated", "organization_id": "a0000000-0000-0000-0000-00000000000a", "app_metadata": {"org_id": "a0000000-0000-0000-0000-00000000000a"}}';

-- Insert an initial row for testing (must pass RLS check)
INSERT INTO public.pdf_dossier_logs (
  organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by
) VALUES (
  'a0000000-0000-0000-0000-00000000000a',
  'e0000000-0000-0000-0000-000000000001',
  'hash_1',
  '00000000-0000-0000-0000-000000000002'
);

-- H1: UPDATE fails with 42501 (insufficient_privilege)
SELECT throws_ok(
  $$ UPDATE public.pdf_dossier_logs SET document_hash_sha256 = 'hash_2' WHERE sla_ledger_entry_id = 'e0000000-0000-0000-0000-000000000001' $$,
  '42501',
  'permission denied for table pdf_dossier_logs',
  'H1/INV-3: UPDATE must throw permission denied'
);

-- H2: DELETE fails with 42501 (insufficient_privilege)
SELECT throws_ok(
  $$ DELETE FROM public.pdf_dossier_logs WHERE sla_ledger_entry_id = 'e0000000-0000-0000-0000-000000000001' $$,
  '42501',
  'permission denied for table pdf_dossier_logs',
  'H2/INV-3: DELETE must throw permission denied'
);

-- H3: Duplicate INSERT with same org, entry, and hash fails (INV-15)
SELECT throws_ok(
  $$ INSERT INTO public.pdf_dossier_logs (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by)
     VALUES ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'hash_1', '00000000-0000-0000-0000-000000000002') $$,
  '23505',
  'duplicate key value violates unique constraint "uq_pdf_dossier_logs_entry_hash"',
  'H3/INV-15: Duplicate entry/hash violates unique constraint'
);

-- H4: Re-generation with same org, entry but DIFFERENT hash succeeds (INV-15)
-- We insert a second row for the same entry with 'hash_2'
SELECT lives_ok(
  $$ INSERT INTO public.pdf_dossier_logs (organization_id, sla_ledger_entry_id, document_hash_sha256, generated_by)
     VALUES ('a0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-000000000001', 'hash_2', '00000000-0000-0000-0000-000000000002') $$,
  'H4/INV-15: Same entry but different hash is allowed (re-generation)'
);

SELECT * FROM finish();
ROLLBACK;
