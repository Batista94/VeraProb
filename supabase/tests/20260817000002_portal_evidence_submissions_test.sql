BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(21);

-- =============================================================================
-- pgTAP: portal_evidence_submissions — Sprint A M2
-- Covers: quarantine table shape, sealed-at-ingest immutability, seal-once
-- finalize/audit fields, status monotonicity (legal + illegal edges), terminal
-- states, soft-delete resurrection block, deny-all RLS grants, append-only.
-- =============================================================================

-- ── Seeds (as postgres: bypasses RLS/grants for fixture setup) ───────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad2a01', 'Org Sub', 'Org Sub SA', '00000000dad2a1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'sub@test.com', 'EXT_SUB', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad2e01', '00000000-0000-0000-0000-00000dad2a01',
   '00000000-0000-0000-0000-00000dad2f01', 'set-sub',
   '00000000-0000-0000-0000-00000dad2aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Exceeded","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad2b01', NOW() + INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad2c01', '00000000-0000-0000-0000-00000dad2a01',
   '00000000-0000-0000-0000-00000dad2e01', '00000000-0000-0000-0000-00000dad2b01',
   NOW() + INTERVAL '24 hours', 5, 'submit', 5, NOW())
ON CONFLICT (id) DO NOTHING;

-- Helper: insert a fresh QUARANTINE submission, return its id.
CREATE OR REPLACE FUNCTION pg_temp.mk_sub(p_path TEXT) RETURNS UUID
LANGUAGE sql AS $$
  INSERT INTO public.portal_evidence_submissions
    (organization_id, queue_entry_id, token_id, quarantine_storage_path,
     file_name, mime_type_declared, file_size_bytes_declared, sha256_client)
  VALUES
    ('00000000-0000-0000-0000-00000dad2a01', '00000000-0000-0000-0000-00000dad2e01',
     '00000000-0000-0000-0000-00000dad2c01', p_path, 'proof.pdf', 'application/pdf',
     2048, repeat('a', 64))
  RETURNING id;
$$;

-- =============================================================================
-- STRUCTURAL TESTS
-- =============================================================================

SELECT has_table('public', 'portal_evidence_submissions',
  'S1: portal_evidence_submissions table exists');

SELECT has_column('public', 'portal_evidence_submissions', 'sha256_server',
  'S2: sha256_server column exists');

SELECT has_column('public', 'portal_evidence_submissions', 'quarantine_storage_path',
  'S3: quarantine_storage_path column exists');

-- S4: status defaults to QUARANTINE
SELECT ok(
  (SELECT column_default LIKE '%QUARANTINE%' FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'portal_evidence_submissions'
      AND column_name = 'status'),
  'S4: status default is QUARANTINE');

-- S5: RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
    WHERE oid = 'public.portal_evidence_submissions'::regclass),
  'S5: RLS enabled on portal_evidence_submissions');

-- S6: no policies (deny-all) for client roles
SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'portal_evidence_submissions'),
  0, 'S6: deny-all — zero RLS policies (service_role only)');

-- S7: authenticated has no table privileges (deny-all)
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.portal_evidence_submissions', 'SELECT'),
  'S7: authenticated cannot SELECT (deny-all)');

-- S8: service_role can SELECT
SELECT ok(
  has_table_privilege('service_role', 'public.portal_evidence_submissions', 'SELECT'),
  'S8: service_role can SELECT');

-- =============================================================================
-- CONSTRAINT TESTS
-- =============================================================================

-- C1: invalid declared mime rejected
SELECT throws_ok(
  $$ INSERT INTO public.portal_evidence_submissions
       (organization_id, queue_entry_id, token_id, quarantine_storage_path,
        file_name, mime_type_declared, file_size_bytes_declared, sha256_client)
     VALUES ('00000000-0000-0000-0000-00000dad2a01','00000000-0000-0000-0000-00000dad2e01',
             '00000000-0000-0000-0000-00000dad2c01','t/x.exe','x.exe',
             'application/x-msdownload', 2048, repeat('a',64)) $$,
  '23514', NULL, 'C1: invalid mime_type_declared rejected');

-- C2: malformed sha256_client rejected
SELECT throws_ok(
  $$ INSERT INTO public.portal_evidence_submissions
       (organization_id, queue_entry_id, token_id, quarantine_storage_path,
        file_name, mime_type_declared, file_size_bytes_declared, sha256_client)
     VALUES ('00000000-0000-0000-0000-00000dad2a01','00000000-0000-0000-0000-00000dad2e01',
             '00000000-0000-0000-0000-00000dad2c01','t/y.pdf','y.pdf',
             'application/pdf', 2048, 'NOTAHASH') $$,
  '23514', NULL, 'C2: malformed sha256_client rejected');

-- C3: oversize declared file rejected (>10MB)
SELECT throws_ok(
  $$ INSERT INTO public.portal_evidence_submissions
       (organization_id, queue_entry_id, token_id, quarantine_storage_path,
        file_name, mime_type_declared, file_size_bytes_declared, sha256_client)
     VALUES ('00000000-0000-0000-0000-00000dad2a01','00000000-0000-0000-0000-00000dad2e01',
             '00000000-0000-0000-0000-00000dad2c01','t/z.pdf','z.pdf',
             'application/pdf', 10485761, repeat('a',64)) $$,
  '23514', NULL, 'C3: oversize declared file rejected');

-- C4: duplicate (token_id, quarantine_storage_path) rejected
SELECT lives_ok(
  $$ SELECT pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/dup.pdf') $$,
  'C4 setup: first submission inserts');
SELECT throws_ok(
  $$ SELECT pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/dup.pdf') $$,
  '23505', NULL, 'C4: duplicate token_id+path rejected (anti-replay)');

-- =============================================================================
-- IMMUTABILITY + STATUS MONOTONICITY
-- =============================================================================

-- IM1: sealed-at-ingest field (sha256_client) mutation blocked
SELECT throws_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET sha256_client = %L WHERE id = %L $$,
         repeat('b',64), pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/im1.pdf')),
  '23001', NULL, 'IM1: sealed sha256_client mutation blocked (INV-9)');

-- IM2: seal-once sha256_server cannot be overwritten once set
DO $$
DECLARE v UUID := pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/im2.pdf');
BEGIN
  UPDATE public.portal_evidence_submissions
     SET sha256_server = repeat('c',64), production_storage_path = 'prod/im2.pdf',
         finalized_at_utc = NOW(), status = 'PENDING_AUDIT'
   WHERE id = v;
  PERFORM set_config('pgtap.im2', v::text, true);
END $$;
SELECT throws_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET sha256_server = %L WHERE id = %L $$,
         repeat('d',64), current_setting('pgtap.im2')::uuid),
  '23001', NULL, 'IM2: seal-once sha256_server re-mutation blocked (INV-9)');

-- ST1: legal QUARANTINE → PENDING_AUDIT
SELECT lives_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET status = 'PENDING_AUDIT' WHERE id = %L $$,
         pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/st1.pdf')),
  'ST1: legal transition QUARANTINE → PENDING_AUDIT');

-- ST2: illegal QUARANTINE → ACCEPTED (must pass through PENDING_AUDIT)
SELECT throws_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET status = 'ACCEPTED' WHERE id = %L $$,
         pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/st2.pdf')),
  '23001', NULL, 'ST2: illegal QUARANTINE → ACCEPTED blocked');

-- ST3: terminal MISMATCH has no outgoing edge
DO $$
DECLARE v UUID := pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/st3.pdf');
BEGIN
  UPDATE public.portal_evidence_submissions SET status = 'MISMATCH' WHERE id = v;
  PERFORM set_config('pgtap.st3', v::text, true);
END $$;
SELECT throws_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET status = 'PENDING_AUDIT' WHERE id = %L $$,
         current_setting('pgtap.st3')::uuid),
  '23001', NULL, 'ST3: terminal MISMATCH cannot transition');

-- ST4: PENDING_AUDIT → ACCEPTED legal (auditor accept)
DO $$
DECLARE v UUID := pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/st4.pdf');
BEGIN
  UPDATE public.portal_evidence_submissions SET status = 'PENDING_AUDIT' WHERE id = v;
  PERFORM set_config('pgtap.st4', v::text, true);
END $$;
SELECT lives_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET status = 'ACCEPTED', audited_by = '00000000-0000-0000-0000-00000dad2b01',
                  audited_at = NOW() WHERE id = %L $$,
         current_setting('pgtap.st4')::uuid),
  'ST4: legal transition PENDING_AUDIT → ACCEPTED');

-- DEL: hard DELETE blocked (append-only)
SELECT throws_ok(
  format($$ DELETE FROM public.portal_evidence_submissions WHERE id = %L $$,
         pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/del.pdf')),
  '23001', NULL, 'DEL: hard DELETE blocked (append-only INV-3)');

-- RES: soft-delete resurrection blocked
DO $$
DECLARE v UUID := pg_temp.mk_sub('00000000-0000-0000-0000-00000dad2c01/res.pdf');
BEGIN
  UPDATE public.portal_evidence_submissions SET deleted_at = NOW() WHERE id = v;
  PERFORM set_config('pgtap.res', v::text, true);
END $$;
SELECT throws_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET deleted_at = NULL WHERE id = %L $$,
         current_setting('pgtap.res')::uuid),
  '23001', NULL, 'RES: cannot resurrect soft-deleted submission (INV-3)');

SELECT * FROM finish();
ROLLBACK;
