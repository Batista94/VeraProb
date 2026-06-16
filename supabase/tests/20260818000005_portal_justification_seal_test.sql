BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(38);

-- =============================================================================
-- pgTAP: portal_justification_seal — Dispute Portal Refactor (Pacote 1)
-- Migration under test: 20260818000005_portal_justification_seal.sql
-- Covers: justification_text column + validity CHECK, sha256_combined_seal,
-- combined-seal computation at finalize, sealed-at-ingest immutability,
-- file-optional path (submit_portal_justification_only +
-- portal_justification_submissions), ledger widening, grants, and the adverse
-- scenarios T1–T15 (plan §6). Anti-oracle: every rejection is opaque 42501.
-- Seed UUIDs use only hex chars (d/a/6 + digits) — 'pjs' is NOT valid hex.
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad6a01','Org6','Org6 SA','00000000dad6a1',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'o6@test.com',
   'EXT6','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6f01','set6','00000000-0000-0000-0000-00000dad6aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad6b01', NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

-- Tokens: submit (cap 10), submit (cap 1, double-submit), expired, read-scope.
INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, token, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad6c01','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-0000dad67001',
   '00000000-0000-0000-0000-00000dad6b01',NOW()+INTERVAL '24 hours',5,'submit',10,NOW()),
  ('00000000-0000-0000-0000-00000dad6c02','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-0000dad67002',
   '00000000-0000-0000-0000-00000dad6b01',NOW()+INTERVAL '24 hours',5,'submit',1,NOW()),
  ('00000000-0000-0000-0000-00000dad6c03','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-0000dad67003',
   '00000000-0000-0000-0000-00000dad6b01',NOW()-INTERVAL '1 hours',5,'submit',5,NOW()-INTERVAL '2 hours'),
  ('00000000-0000-0000-0000-00000dad6c04','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-0000dad67004',
   '00000000-0000-0000-0000-00000dad6b01',NOW()+INTERVAL '24 hours',5,'read',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- SCHEMA: columns, constraints, table, ledger widening
-- =============================================================================
SELECT has_column('public','portal_evidence_submissions','justification_text',
  'S1: portal_evidence_submissions has justification_text');
SELECT ok(
  (SELECT is_nullable='YES' FROM information_schema.columns
    WHERE table_schema='public' AND table_name='portal_evidence_submissions'
      AND column_name='justification_text'),
  'S2: justification_text is NULLABLE at table level (legacy rows survive)');
SELECT has_column('public','dispute_evidence_attachments','sha256_combined_seal',
  'S3: dispute_evidence_attachments has sha256_combined_seal');
SELECT ok(
  (SELECT is_nullable='YES' FROM information_schema.columns
    WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
      AND column_name='sha256_combined_seal'),
  'S4: sha256_combined_seal is NULLABLE (file-only/legacy attachments)');
SELECT has_table('public','portal_justification_submissions',
  'S5: portal_justification_submissions table exists');
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
    WHERE relname='portal_justification_submissions'
      AND relnamespace='public'::regnamespace),
  'S6: portal_justification_submissions has RLS enabled (INV-2)');
SELECT ok(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='chk_ledger_type'
     LIMIT 1) LIKE '%PORTAL_JUSTIFICATION_SUBMITTED%',
  'S7: chk_ledger_type admits PORTAL_JUSTIFICATION_SUBMITTED (canonical name)');

-- =============================================================================
-- create_portal_submission — justification validation (T1–T5, T7–T10, T14)
-- =============================================================================
-- T1: empty justification rejected (anti-oracle 42501)
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67001','f.pdf','application/pdf',2048,repeat('1',64),'') $$,
  '42501', NULL, 'T1: empty justification rejected');
-- T2: whitespace-only (10 spaces) rejected (trim < 10)
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67001','f.pdf','application/pdf',2048,repeat('2',64),'          ') $$,
  '42501', NULL, 'T2: whitespace-only justification rejected (trim < 10)');
-- T3: 9 chars rejected
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67001','f.pdf','application/pdf',2048,repeat('3',64),'123456789') $$,
  '42501', NULL, 'T3: 9-char justification rejected');
-- T4: exactly 10 chars accepted
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad67001','t4.pdf','application/pdf',2048,repeat('4',64),'1234567890');
  PERFORM set_config('t.sub_t4', r.submission_id::text, true);
END $$;
SELECT is(
  (SELECT justification_text FROM public.portal_evidence_submissions
    WHERE id=current_setting('t.sub_t4')::uuid),
  '1234567890', 'T4: 10-char justification accepted + persisted verbatim');
-- T5: 4001 chars rejected
SELECT throws_ok(
  format($$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67001','f.pdf','application/pdf',2048,%L,%L) $$,
       repeat('5',64), repeat('x',4001)),
  '42501', NULL, 'T5: 4001-char justification rejected (cap 4000)');
-- T9: control char rejected (regex). NUL (\x00) cannot exist in a PG text value
-- (rejected at the protocol layer, 54000), so we exercise the regex with BEL
-- (\x07) — a C0 control char PG permits in text but the CHECK/RPC must reject.
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67001','f.pdf','application/pdf',2048,repeat('9',64),
       'valid start' || chr(7) || 'and end here') $$,
  '42501', NULL, 'T9: control char (BEL \x07) justification rejected');

-- T7: <script> stored RAW (escape only at render/export — never at ingest)
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad67001','t7.pdf','application/pdf',2048,repeat('7',64),
    '<script>alert(1)</script> contesto a multa por falha tecnica.');
  PERFORM set_config('t.sub_t7', r.submission_id::text, true);
END $$;
SELECT is(
  (SELECT justification_text FROM public.portal_evidence_submissions
    WHERE id=current_setting('t.sub_t7')::uuid),
  '<script>alert(1)</script> contesto a multa por falha tecnica.',
  'T7: <script> stored raw verbatim (no ingest-time HTML encoding)');

-- T10: SQL-injection text stays a literal (parameterized path — never executes)
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad67001','t10.pdf','application/pdf',2048,repeat('8',64),
    $j$'; DROP TABLE public.portal_evidence_submissions; -- contesto formalmente$j$);
  PERFORM set_config('t.sub_t10', r.submission_id::text, true);
END $$;
SELECT is(
  (SELECT justification_text FROM public.portal_evidence_submissions
    WHERE id=current_setting('t.sub_t10')::uuid),
  $j$'; DROP TABLE public.portal_evidence_submissions; -- contesto formalmente$j$,
  'T10: SQL-injection text persists as a literal (parameterized)');
SELECT has_table('public','portal_evidence_submissions',
  'T10b: target table still exists (injection did not execute)');

-- T8: =IMPORTXML formula-injection stored raw (CSV prefix is an export concern)
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad67001','t8.pdf','application/pdf',2048,repeat('a',64),
    '=IMPORTXML(A1,"//x") justificativa de contestacao formal.');
  PERFORM set_config('t.sub_t8', r.submission_id::text, true);
END $$;
SELECT is(
  (SELECT left(justification_text,10) FROM public.portal_evidence_submissions
    WHERE id=current_setting('t.sub_t8')::uuid),
  '=IMPORTXML',
  'T8: =IMPORTXML stored raw (formula-injection escaped only at export)');

-- T14: 4000 multibyte Unicode chars accepted (char_length, NOT octet_length)
DO $$
DECLARE r RECORD;
BEGIN
  -- U+00E7 'ç' = 2 bytes UTF-8: 4000 chars = 8000 bytes, char_length = 4000.
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad67001','t14.pdf','application/pdf',2048,repeat('b',64),
    repeat(U&'\00E7', 4000));
  PERFORM set_config('t.sub_t14', r.submission_id::text, true);
END $$;
SELECT is(
  (SELECT char_length(justification_text) FROM public.portal_evidence_submissions
    WHERE id=current_setting('t.sub_t14')::uuid),
  4000,
  'T14: 4000 multibyte chars accepted (char_length passes; octet_length=8000)');

-- =============================================================================
-- register_portal_evidence — combined seal computation (INV-9)
-- =============================================================================
DO $$
DECLARE r RECORD; v UUID;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad67001','seal.pdf','application/pdf',2048,repeat('c',64),
    'Justificativa para o selo combinado verificavel.');
  PERFORM set_config('t.sub_seal', r.submission_id::text, true);
  PERFORM set_config('t.just_seal',
    (SELECT justification_text FROM public.portal_evidence_submissions WHERE id=r.submission_id), true);
  v := public.register_portal_evidence(r.submission_id, repeat('d',64),'application/pdf',2048);
  PERFORM set_config('t.att_seal', v::text, true);
END $$;
SELECT ok(
  (SELECT sha256_combined_seal ~ '^[a-f0-9]{64}$' FROM public.dispute_evidence_attachments
    WHERE id=current_setting('t.att_seal')::uuid),
  'SEAL1: sha256_combined_seal is a valid 64-hex string after finalize (INV-9)');
SELECT is(
  (SELECT sha256_combined_seal FROM public.dispute_evidence_attachments
    WHERE id=current_setting('t.att_seal')::uuid),
  encode(extensions.digest(repeat('d',64) || ':' || current_setting('t.just_seal'),'sha256'),'hex'),
  'SEAL2: combined seal = sha256(sha256_server || '':'' || justification)');
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type='PORTAL_EVIDENCE_FINALIZED'
      AND payload->>'submission_id'=current_setting('t.sub_seal')
      AND payload ? 'sha256_combined_seal'),
  1, 'SEAL3: PORTAL_EVIDENCE_FINALIZED payload carries sha256_combined_seal');

-- =============================================================================
-- T12: direct UPDATE of sealed testimony / seal → restrict_violation (23001)
-- =============================================================================
SET client_min_messages TO 'ERROR';
SELECT throws_ok(
  format($$ UPDATE public.portal_evidence_submissions
              SET justification_text='tampered post-finalize attempt!' WHERE id=%L $$,
         current_setting('t.sub_seal')),
  '23001', NULL,
  'T12: UPDATE justification_text post-ingest blocked (immutability INV-3/INV-9)');
SELECT throws_ok(
  format($$ UPDATE public.dispute_evidence_attachments
              SET sha256_combined_seal=%L WHERE id=%L $$,
         repeat('0',64), current_setting('t.att_seal')),
  '23001', NULL,
  'T12b: UPDATE sha256_combined_seal blocked (seal-once INV-9)');
RESET client_min_messages;

-- =============================================================================
-- T11/T13/T15: token cap, expiry, scope
-- =============================================================================
-- T15: read-scope token rejected on submit (scope enforced, anti-oracle)
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67004','f.pdf','application/pdf',2048,repeat('1',64),
       'Justificativa valida porem token e de leitura.') $$,
  '42501', NULL, 'T15: read-scope token rejected on submit');
-- T13: expired token rejected
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67003','f.pdf','application/pdf',2048,repeat('1',64),
       'Justificativa valida porem o token expirou agora.') $$,
  '42501', NULL, 'T13: expired token rejected');
-- T11: per-token cap (max_submissions=1) — first ok, second rejected
SELECT lives_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67002','cap1.pdf','application/pdf',2048,repeat('2',64),
       'Primeira submissao do token com limite unitario.') $$,
  'T11a: cap token first submission ok');
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad67002','cap2.pdf','application/pdf',2048,repeat('3',64),
       'Segunda submissao deve exceder o limite do token.') $$,
  '42501', NULL, 'T11b: per-token cap enforced (double-submit blocked)');

-- =============================================================================
-- submit_portal_justification_only — file-optional (anexo opcional) contest
-- =============================================================================
DO $$
DECLARE v UUID;
BEGIN
  v := public.submit_portal_justification_only(
    '00000000-0000-0000-0000-0000dad67001',
    'Contesto sem anexo: a infracao decorre de falha do sistema.');
  PERFORM set_config('t.jo1', v::text, true);
END $$;
SELECT is(
  (SELECT status FROM public.portal_justification_submissions WHERE id=current_setting('t.jo1')::uuid),
  'PENDING_AUDIT', 'JO1: justification-only contest is born PENDING_AUDIT (no bytes to re-hash)');
SELECT is(
  (SELECT sha256_justification_seal FROM public.portal_justification_submissions
    WHERE id=current_setting('t.jo1')::uuid),
  encode(extensions.digest('Contesto sem anexo: a infracao decorre de falha do sistema.','sha256'),'hex'),
  'JO2: justification-only seal = sha256(justification) (INV-9)');
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type='PORTAL_JUSTIFICATION_SUBMITTED'
      AND payload->>'pjs_id'=current_setting('t.jo1')),
  1, 'JO3: PORTAL_JUSTIFICATION_SUBMITTED ledger fact logged (INV-3)');
-- JO4: control char rejected opaquely
SELECT throws_ok(
  $$ SELECT public.submit_portal_justification_only(
       '00000000-0000-0000-0000-0000dad67001', 'start' || chr(7) || 'bad control char here') $$,
  '42501', NULL, 'JO4: control char in justification-only rejected (42501)');
-- JO5: read-scope token cannot submit justification-only
SELECT throws_ok(
  $$ SELECT public.submit_portal_justification_only(
       '00000000-0000-0000-0000-0000dad67004', 'Justificativa valida com token de leitura apenas.') $$,
  '42501', NULL, 'JO5: read-scope token rejected on justification-only (scope)');
-- JO6: post-ingest UPDATE blocked (append-only)
SET client_min_messages TO 'ERROR';
SELECT throws_ok(
  format($$ UPDATE public.portal_justification_submissions
              SET justification_text='tampered' WHERE id=%L $$, current_setting('t.jo1')),
  '23001', NULL,
  'JO6: justification-only record is immutable post-ingest (INV-3)');
RESET client_min_messages;

-- =============================================================================
-- LEDGER: submitted fact carries justification hash (auditable), not raw text
-- =============================================================================
SELECT ok(
  (SELECT payload ? 'justification_sha256' FROM public.sla_audit_ledger_v2
    WHERE type='PORTAL_EVIDENCE_SUBMITTED'
      AND payload->>'submission_id'=current_setting('t.sub_t4')) IS TRUE,
  'L1: PORTAL_EVIDENCE_SUBMITTED payload carries justification_sha256 (not raw text)');

-- =============================================================================
-- GRANTS
-- =============================================================================
SELECT ok(
  has_function_privilege('service_role',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE'),
  'GR1: create_portal_submission (8-arg) is service_role-only');
SELECT ok(
  has_function_privilege('service_role',
    'public.submit_portal_justification_only(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('anon',
    'public.submit_portal_justification_only(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.submit_portal_justification_only(uuid,text)','EXECUTE'),
  'GR2: submit_portal_justification_only is service_role-only');
SELECT ok(
  has_function_privilege('authenticated',
    'public.list_portal_justification_submissions(uuid,uuid)','EXECUTE')
  AND NOT has_function_privilege('anon',
    'public.list_portal_justification_submissions(uuid,uuid)','EXECUTE'),
  'GR3: list_portal_justification_submissions is authenticated-only');
-- Old 7-arg overload must be gone (DROP'd → PostgREST resolves the new shape).
SELECT is(
  (SELECT count(*)::int FROM pg_proc WHERE proname='create_portal_submission' AND pronargs=7),
  0, 'GR4: old 7-arg create_portal_submission overload dropped');

SELECT * FROM finish();
ROLLBACK;
