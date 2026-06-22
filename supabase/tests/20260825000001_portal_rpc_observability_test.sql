BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- =============================================================================
-- pgTAP: portal_rpc_observability — PKG1
-- Migration under test: 20260825000001_portal_rpc_observability.sql
-- Covers: DETAIL tokens (PORTAL_SUBMIT_REJECTED:<CODE>) reachable ONLY via
-- PG_EXCEPTION_DETAIL (never the opaque message), QUARANTINE hash idempotency
-- keyed on (token_id, sha256_client), the INV-18 Zero-Trust ordering (token
-- validated before the idempotency reuse), and grant parity.
-- Seed UUIDs use only hex chars (d/a/8 + digits).
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad8a01','Org8','Org8 SA','00000000dad8a1',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'o8@test.com',
   'EXT8','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8f01','set8','00000000-0000-0000-0000-00000dad8aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad8b01', NOW()+INTERVAL '5 days'),
  ('00000000-0000-0000-0000-00000dad8e02','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8f02','set8','00000000-0000-0000-0000-00000dad8aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"A"}'::jsonb, 'applied', NULL,NULL,NULL)
ON CONFLICT (id) DO NOTHING;

-- Tokens: c01 main (cap 10), c02 cap-1, c03 revoke-target (cap 5), c04 applied-queue.
INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, token, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad8c01','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-0000dad87001',
   '00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '24 hours',50,'submit',10,NOW()),
  ('00000000-0000-0000-0000-00000dad8c02','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-0000dad87002',
   '00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '24 hours',50,'submit',1,NOW()),
  ('00000000-0000-0000-0000-00000dad8c03','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-0000dad87003',
   '00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '24 hours',50,'submit',5,NOW()),
  ('00000000-0000-0000-0000-00000dad8c04','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e02','00000000-0000-0000-0000-0000dad87004',
   '00000000-0000-0000-0000-00000dad8b01',NOW()+INTERVAL '24 hours',50,'submit',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- DETAIL tokens — visible ONLY via PG_EXCEPTION_DETAIL (anti-oracle: message stays opaque)
-- =============================================================================
-- DET-MIME (checked before token, so any token value reaches it)
DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','f.pdf','application/x-evil',2048,repeat('1',64),
    'Justificativa valida para o teste de detail.');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_mime', d, true);
END $$;
SELECT is(current_setting('t.det_mime'),
  'PORTAL_SUBMIT_REJECTED:MIME_UNSUPPORTED', 'DET-MIME');

DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','f.pdf','application/pdf',0,repeat('1',64),
    'Justificativa valida para o teste de detail.');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_size', d, true);
END $$;
SELECT is(current_setting('t.det_size'),
  'PORTAL_SUBMIT_REJECTED:FILE_SIZE_OUT_OF_RANGE', 'DET-SIZE');

DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','f.pdf','application/pdf',2048,'not-a-hash',
    'Justificativa valida para o teste de detail.');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_sha', d, true);
END $$;
SELECT is(current_setting('t.det_sha'),
  'PORTAL_SUBMIT_REJECTED:SHA256_INVALID', 'DET-SHA');

DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','f.pdf','application/pdf',2048,repeat('1',64),'');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_just', d, true);
END $$;
SELECT is(current_setting('t.det_just'),
  'PORTAL_SUBMIT_REJECTED:JUSTIFICATION_INVALID', 'DET-JUST');

-- DET-TOKEN: all inputs valid, token does not exist
DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad8ffff','f.pdf','application/pdf',2048,repeat('1',64),
    'Justificativa valida porem token inexistente.');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_token', d, true);
END $$;
SELECT is(current_setting('t.det_token'),
  'PORTAL_SUBMIT_REJECTED:TOKEN_SOVEREIGNTY', 'DET-TOKEN');

-- DET-QUEUE: submit token whose queue is 'applied' (not disputed)
DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87004','f.pdf','application/pdf',2048,repeat('1',64),
    'Justificativa valida porem fila nao esta disputada.');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_queue', d, true);
END $$;
SELECT is(current_setting('t.det_queue'),
  'PORTAL_SUBMIT_REJECTED:QUEUE_STATE_INVALID', 'DET-QUEUE');

-- DET-CAP: cap-1 token — first submit ok, a DIFFERENT-sha second hits the cap
SELECT lives_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad87002','cap1.pdf','application/pdf',2048,repeat('1',64),
       'Primeira submissao do token cap unitario.') $$,
  'DET-CAP-pre: cap-1 token first submission ok');
DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87002','cap2.pdf','application/pdf',2048,repeat('2',64),
    'Segunda submissao com bytes diferentes excede o cap.');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.det_cap', d, true);
END $$;
SELECT is(current_setting('t.det_cap'),
  'PORTAL_SUBMIT_REJECTED:SUBMISSION_CAP_EXCEEDED', 'DET-CAP');

-- =============================================================================
-- IDEMP1: same (token, sha) twice while QUARANTINE → reuse, no new row
-- =============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','i1.pdf','application/pdf',2048,repeat('a',64),
    'Justificativa de contestacao idempotente um.');
  PERFORM set_config('t.idemp1_a', r.submission_id::text, true);
  PERFORM set_config('t.idemp1_path_a', r.quarantine_path, true);
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87001','i1-retry.pdf','application/pdf',2048,repeat('a',64),
    'Justificativa de contestacao idempotente um.');
  PERFORM set_config('t.idemp1_b', r.submission_id::text, true);
  PERFORM set_config('t.idemp1_path_b', r.quarantine_path, true);
END $$;
SELECT is(current_setting('t.idemp1_b'), current_setting('t.idemp1_a'),
  'IDEMP1a: retry of same (token,sha) returns the same submission_id');
SELECT is(current_setting('t.idemp1_path_b'), current_setting('t.idemp1_path_a'),
  'IDEMP1b: retry reuses the same quarantine_path (no re-mint)');
SELECT is(
  (SELECT count(*)::int FROM public.portal_evidence_submissions
    WHERE token_id='00000000-0000-0000-0000-00000dad8c01' AND deleted_at IS NULL),
  1, 'IDEMP1c: exactly one quarantine row persisted (retry deduped, no slot burned)');

-- =============================================================================
-- IDEMP2: cap-1 token (c02) idempotent retry does NOT exceed the cap
-- =============================================================================
SELECT lives_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad87002','cap1-retry.pdf','application/pdf',2048,repeat('1',64),
       'Primeira submissao do token cap unitario.') $$,
  'IDEMP2a: identical-sha retry under cap-1 succeeds (deduped, not cap-rejected)');
SELECT is(
  (SELECT count(*)::int FROM public.portal_evidence_submissions
    WHERE token_id='00000000-0000-0000-0000-00000dad8c02' AND deleted_at IS NULL),
  1, 'IDEMP2b: cap-1 token still has exactly one row after the retry');

-- =============================================================================
-- VETO1 (INV-18): revoked token with a matching prior sha STILL fails opaquely
-- =============================================================================
DO $$ BEGIN
  PERFORM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad87003','v.pdf','application/pdf',2048,repeat('c',64),
    'Justificativa antes da revogacao do token.');
END $$;
UPDATE public.dispute_portal_tokens
   SET revoked_at_utc = NOW()
 WHERE id='00000000-0000-0000-0000-00000dad8c03';
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad87003','v-retry.pdf','application/pdf',2048,repeat('c',64),
       'Tentativa de reuso apos revogacao.') $$,
  '42501', NULL,
  'VETO1: revoked token on the idempotency path still raises 42501 (token before dedup)');

-- =============================================================================
-- JO-DET: submit_portal_justification_only carries the DETAIL token too
-- =============================================================================
DO $$
DECLARE d TEXT;
BEGIN
  PERFORM public.submit_portal_justification_only(
    '00000000-0000-0000-0000-0000dad87001', 'short');
EXCEPTION WHEN insufficient_privilege THEN
  GET STACKED DIAGNOSTICS d = PG_EXCEPTION_DETAIL;
  PERFORM set_config('t.jo_det', d, true);
END $$;
SELECT is(current_setting('t.jo_det'),
  'PORTAL_SUBMIT_REJECTED:JUSTIFICATION_INVALID', 'JO-DET: justification-only carries DETAIL');

-- =============================================================================
-- GR1: grant parity preserved after CREATE OR REPLACE
-- =============================================================================
SELECT ok(
  has_function_privilege('service_role',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE')
  AND NOT has_function_privilege('anon',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE'),
  'GR1: create_portal_submission is service_role-only (DETAIL never reaches anon/authenticated)');

SELECT * FROM finish();
ROLLBACK;
