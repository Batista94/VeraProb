BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(23);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000ea001', 'Org EA', 'Org EA SA', '00000000000ea1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'ea@test.com', 'EXT_EA', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000ea0e1', '00000000-0000-0000-0000-0000000ea001',
   '00000000-0000-0000-0000-0000000ea0f1', 'set-ea', 'contract-ea',
   '{"fine_cents": 200000}'::jsonb, 'disputed')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_evidence_attachments
  (id, organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, verification_status, uploaded_by, attached_at)
VALUES
  ('00000000-0000-0000-0000-0000000ea0d1', '00000000-0000-0000-0000-0000000ea001',
   '00000000-0000-0000-0000-0000000ea0e1',
   '00000000-0000-0000-0000-0000000ea001/00000000-0000-0000-0000-0000000ea0e1/a.jpg',
   'a.jpg', 'image/jpeg', 1024,
   'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
   'PENDING', '00000000-0000-0000-0000-0000000ea0b1', NOW());

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_table('public', 'dispute_evidence_attachments',
  'dispute_evidence_attachments table exists');

SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
       AND column_name='organization_id' AND data_type='uuid'),
  'organization_id exists (UUID)');

SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
       AND column_name='queue_entry_id' AND data_type='uuid'),
  'queue_entry_id exists (UUID)');

SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
       AND column_name='verification_status' AND column_default LIKE '%PENDING%'),
  'verification_status defaults to PENDING');

SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
       AND column_name='attached_at' AND data_type='timestamp with time zone'),
  'attached_at is TIMESTAMPTZ (INV-6)');

SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
       AND column_name='hash_verified_at' AND data_type='timestamp with time zone'),
  'hash_verified_at is TIMESTAMPTZ (INV-6)');

-- ── Constraints ──────────────────────────────────────────────────────────────
SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
     WHERE conname='chk_evidence_mime'
       AND conrelid='public.dispute_evidence_attachments'::regclass),
  'chk_evidence_mime constrains the MIME domain');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
     WHERE conname='chk_evidence_size'
       AND conrelid='public.dispute_evidence_attachments'::regclass),
  'chk_evidence_size bounds file_size_bytes (1B-10MB)');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
     WHERE conname='chk_evidence_hash_format'
       AND conrelid='public.dispute_evidence_attachments'::regclass),
  'chk_evidence_hash_format enforces 64-char lowercase hex (INV-9)');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
     WHERE conname='chk_evidence_verif'
       AND conrelid='public.dispute_evidence_attachments'::regclass),
  'chk_evidence_verif constrains verification_status domain');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
     WHERE conname='uq_dea_hash_per_queue'
       AND conrelid='public.dispute_evidence_attachments'::regclass),
  'uq_dea_hash_per_queue dedupes hash per (org, queue)');

-- ── RLS + policies (INV-2, INV-22) ───────────────────────────────────────────
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
     WHERE oid='public.dispute_evidence_attachments'::regclass),
  'RLS enabled on dispute_evidence_attachments');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policies
     WHERE tablename='dispute_evidence_attachments' AND policyname='dea_select_own_org'),
  'dea_select_own_org SELECT policy exists');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policies
     WHERE tablename='dispute_evidence_attachments' AND policyname='dea_update_own_org'),
  'dea_update_own_org UPDATE policy exists');

SELECT is(
  (SELECT count(*)::int FROM pg_policies
     WHERE tablename='dispute_evidence_attachments' AND cmd='INSERT'),
  0, 'no client-side INSERT policy (B4: RPC-only insert)');

-- ── Behavioral triggers (INV-9, INV-3, B3) ───────────────────────────────────
SELECT throws_ok(
  $$ UPDATE public.dispute_evidence_attachments
        SET sha256_hash = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
      WHERE id='00000000-0000-0000-0000-0000000ea0d1' $$,
  '23001', NULL,
  'mutating a sealed field (sha256_hash) is blocked (INV-9)');

SELECT throws_ok(
  $$ DELETE FROM public.dispute_evidence_attachments
      WHERE id='00000000-0000-0000-0000-0000000ea0d1' $$,
  '23001', NULL,
  'hard DELETE is blocked (append-only)');

SELECT lives_ok(
  $$ UPDATE public.dispute_evidence_attachments
        SET deleted_at = NOW()
      WHERE id='00000000-0000-0000-0000-0000000ea0d1' $$,
  'soft-delete (set deleted_at) is allowed');

SELECT throws_ok(
  $$ UPDATE public.dispute_evidence_attachments
        SET deleted_at = NULL
      WHERE id='00000000-0000-0000-0000-0000000ea0d1' $$,
  '23001', NULL,
  'un-soft-delete (resurrect retracted evidence) is blocked (B3)');

-- ── Data API grants (INV-DATA-API-GRANT) ─────────────────────────────────────
SELECT ok(
  has_table_privilege('authenticated', 'public.dispute_evidence_attachments', 'SELECT'),
  'authenticated has SELECT');

SELECT ok(
  has_table_privilege('authenticated', 'public.dispute_evidence_attachments', 'UPDATE'),
  'authenticated has UPDATE (soft-delete)');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.dispute_evidence_attachments', 'INSERT'),
  'authenticated has NO INSERT (RPC-only path, B4)');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.dispute_evidence_attachments', 'DELETE'),
  'authenticated has NO DELETE (append-only, INV-3)');

SELECT * FROM finish();
ROLLBACK;
