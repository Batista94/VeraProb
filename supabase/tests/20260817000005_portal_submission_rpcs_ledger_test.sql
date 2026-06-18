BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(32);

-- =============================================================================
-- pgTAP: portal_submission_rpcs_ledger — Sprint A M5
-- Covers: ledger widening, dea provenance, and all six pipeline RPCs
-- (create / register / fail / audit / acknowledge_via_portal / internal).
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad5a01','Org5','Org5 SA','00000000dad5a1',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'o5@test.com',
   'EXT5','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad5e01','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5f01','set5','00000000-0000-0000-0000-00000dad5aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad5b01', NOW()+INTERVAL '5 days'),
  ('00000000-0000-0000-0000-00000dad5e02','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5f02','set5','00000000-0000-0000-0000-00000dad5aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"A"}'::jsonb, 'applied', NULL,NULL,NULL),
  ('00000000-0000-0000-0000-00000dad5e03','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5f03','set5','00000000-0000-0000-0000-00000dad5aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"A2"}'::jsonb, 'applied', NULL,NULL,NULL),
  ('00000000-0000-0000-0000-00000dad5e04','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5f04','set5','00000000-0000-0000-0000-00000dad5aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"A3"}'::jsonb, 'applied', NULL,NULL,NULL),
  ('00000000-0000-0000-0000-00000dad5e05','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5f05','set5','00000000-0000-0000-0000-00000dad5aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D2","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad5b01', NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

-- Tokens (explicit token value so RPCs can be called by token).
INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, token, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad5c01','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e01','00000000-0000-0000-0000-0000dad57001',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',5,'submit',5,NOW()),
  ('00000000-0000-0000-0000-00000dad5c03','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e01','00000000-0000-0000-0000-0000dad57003',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',5,'submit',1,NOW()),
  ('00000000-0000-0000-0000-00000dad5c04','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e01','00000000-0000-0000-0000-0000dad57004',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',5,'read',5,NOW()),
  ('00000000-0000-0000-0000-00000dad5c02','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e02','00000000-0000-0000-0000-0000dad57002',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',5,'read',5,NOW()),
  ('00000000-0000-0000-0000-00000dad5c05','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e03','00000000-0000-0000-0000-0000dad57005',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',5,'read',5,NOW()),
  ('00000000-0000-0000-0000-00000dad5c06','00000000-0000-0000-0000-00000dad5a01',
   '00000000-0000-0000-0000-00000dad5e05','00000000-0000-0000-0000-0000dad57006',
   '00000000-0000-0000-0000-00000dad5b01',NOW()+INTERVAL '24 hours',5,'submit',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- Served-snapshot facts for the ack flow (what read_dispute_portal would log).
INSERT INTO public.sla_audit_ledger_v2
  (organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad5a01','DISPUTE_PORTAL_TOKEN_ACCESSED','PORTAL',
   'set5','00000000-0000-0000-0000-00000dad5aa1',0,
   jsonb_build_object('token_id','00000000-0000-0000-0000-00000dad5c02',
                      'snapshot_hash',repeat('e',64)), NOW()),
  ('00000000-0000-0000-0000-00000dad5a01','DISPUTE_PORTAL_TOKEN_ACCESSED','PORTAL',
   'set5','00000000-0000-0000-0000-00000dad5aa1',0,
   jsonb_build_object('token_id','00000000-0000-0000-0000-00000dad5c05',
                      'snapshot_hash',repeat('f',64)), NOW());

-- =============================================================================
-- WIDENING + PROVENANCE
-- =============================================================================
SELECT ok(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='chk_ledger_type'
     LIMIT 1) LIKE '%SANCTION_ACKNOWLEDGED%',
  'W1: chk_ledger_type admits SANCTION_ACKNOWLEDGED (canonical name)');
SELECT ok(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='chk_ledger_type'
     LIMIT 1) LIKE '%PORTAL_EVIDENCE_FINALIZED%',
  'W2: chk_ledger_type admits PORTAL_EVIDENCE_FINALIZED');
SELECT has_column('public','dispute_evidence_attachments','submission_id',
  'D1: dea has submission_id provenance column');
SELECT ok(
  (SELECT is_nullable='YES' FROM information_schema.columns
    WHERE table_schema='public' AND table_name='dispute_evidence_attachments'
      AND column_name='uploaded_by'),
  'D2: dea.uploaded_by is now nullable (portal provenance)');

-- =============================================================================
-- create_portal_submission
-- =============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad57001', 'p1.pdf','application/pdf',2048,repeat('1',64),
    'Justificativa de contestacao da submissao um.');
  PERFORM set_config('t.sub1', r.submission_id::text, true);
  PERFORM set_config('t.path1', r.quarantine_path, true);
END $$;
SELECT ok(current_setting('t.sub1') IS NOT NULL, 'CS1: create_portal_submission #1 returns id');
SELECT ok(
  current_setting('t.path1') LIKE '00000000-0000-0000-0000-00000dad5c01/%',
  'CS2: quarantine path is {token_id}/... (no org_id, anti-inference)');

-- CS3: read-scoped token rejected on submit endpoint (42501, anti-oracle)
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad57004','x.pdf','application/pdf',2048,repeat('2',64),
       'Justificativa valida mas token de leitura.') $$,
  '42501', NULL, 'CS3: read token rejected on submit (scope enforced)');

-- CS4: per-token cap (max_submissions=1) — first ok, second rejected
SELECT lives_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad57003','c1.pdf','application/pdf',2048,repeat('3',64),
       'Justificativa da primeira submissao do token cap.') $$,
  'CS4a: cap token first submission ok');
SELECT throws_ok(
  $$ SELECT public.create_portal_submission(
       '00000000-0000-0000-0000-0000dad57003','c2.pdf','application/pdf',2048,repeat('4',64),
       'Justificativa da segunda submissao que excede o cap.') $$,
  '42501', NULL, 'CS4b: per-token submission cap enforced');

-- Second main-flow submission (for fail path) + third (for audit reject).
DO $$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad57001','p2.pdf','application/pdf',2048,repeat('5',64),
    'Justificativa de contestacao da submissao dois.');
  PERFORM set_config('t.sub2', r.submission_id::text, true);
  SELECT * INTO r FROM public.create_portal_submission(
    '00000000-0000-0000-0000-0000dad57006','p3.pdf','application/pdf',2048,repeat('6',64),
    'Justificativa de contestacao da submissao tres.');
  PERFORM set_config('t.sub3', r.submission_id::text, true);
END $$;

-- =============================================================================
-- register_portal_evidence
-- =============================================================================
DO $$
DECLARE v UUID;
BEGIN
  v := public.register_portal_evidence(
    current_setting('t.sub1')::uuid, repeat('a',64),'application/pdf',2048);
  PERFORM set_config('t.att1', v::text, true);
END $$;
SELECT is(
  (SELECT status FROM public.portal_evidence_submissions WHERE id=current_setting('t.sub1')::uuid),
  'PENDING_AUDIT', 'RP1: submission → PENDING_AUDIT after finalize');
SELECT is(
  (SELECT verification_status FROM public.dispute_evidence_attachments WHERE id=current_setting('t.att1')::uuid),
  'VERIFIED', 'RP2: attachment is VERIFIED (server-side hash)');
SELECT ok(
  (SELECT uploaded_by IS NULL AND submission_id=current_setting('t.sub1')::uuid
     FROM public.dispute_evidence_attachments WHERE id=current_setting('t.att1')::uuid),
  'RP3: attachment has portal provenance (uploaded_by NULL, submission_id set)');
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type='PORTAL_EVIDENCE_FINALIZED' AND payload->>'submission_id'=current_setting('t.sub1')),
  1, 'RP4: PORTAL_EVIDENCE_FINALIZED ledger fact logged (INV-3)');
-- RP5: idempotent replay returns the same attachment
SELECT is(
  public.register_portal_evidence(current_setting('t.sub1')::uuid, repeat('a',64),'application/pdf',2048),
  current_setting('t.att1')::uuid, 'RP5: register replay is idempotent (same attachment)');

-- =============================================================================
-- fail_portal_submission
-- =============================================================================
SELECT lives_ok(
  $$ SELECT public.fail_portal_submission(current_setting('t.sub2')::uuid,'HASH_MISMATCH','x') $$,
  'FP1: fail_portal_submission(HASH_MISMATCH) executes');
SELECT is(
  (SELECT status FROM public.portal_evidence_submissions WHERE id=current_setting('t.sub2')::uuid),
  'MISMATCH', 'FP2: submission → MISMATCH');
SELECT is(
  (SELECT count(*)::int FROM public.dispute_evidence_attachments WHERE submission_id=current_setting('t.sub2')::uuid),
  0, 'FP3: no attachment created for a mismatched submission (INV-9)');
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type='PORTAL_EVIDENCE_HASH_MISMATCH' AND payload->>'submission_id'=current_setting('t.sub2')),
  1, 'FP4: PORTAL_EVIDENCE_HASH_MISMATCH ledger fact logged');

-- =============================================================================
-- audit_portal_submission (authenticated)
-- =============================================================================
-- Finalize sub3 so it is PENDING_AUDIT, then auditor rejects it.
DO $$ BEGIN
  PERFORM public.register_portal_evidence(
    current_setting('t.sub3')::uuid, repeat('b',64),'application/pdf',2048);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad5b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad5a01","role":"TENANT_ADMIN"}}';
-- AP1: accept sub1
SELECT lives_ok(
  $$ SELECT public.audit_portal_submission('00000000-0000-0000-0000-00000dad5a01',
       current_setting('t.sub1')::uuid,'accept','00000000-0000-0000-0000-00000dad5b01') $$,
  'AP1: auditor accepts a PENDING_AUDIT submission');
-- AP2: reject sub3
SELECT lives_ok(
  $$ SELECT public.audit_portal_submission('00000000-0000-0000-0000-00000dad5a01',
       current_setting('t.sub3')::uuid,'reject','00000000-0000-0000-0000-00000dad5b01') $$,
  'AP2: auditor rejects a PENDING_AUDIT submission');
RESET ROLE;

SELECT is(
  (SELECT status FROM public.portal_evidence_submissions WHERE id=current_setting('t.sub1')::uuid),
  'ACCEPTED', 'AP3: accepted submission → ACCEPTED');
SELECT is(
  (SELECT count(*)::int FROM public.dispute_evidence_attachments
    WHERE submission_id=current_setting('t.sub3')::uuid AND deleted_at IS NOT NULL),
  1, 'AP4: rejected submission soft-deletes its attachment');

-- AP5: cross-org auditor blocked (42501, INV-22)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad5b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad5a02","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT public.audit_portal_submission('00000000-0000-0000-0000-00000dad5a01',
       current_setting('t.sub1')::uuid,'accept','00000000-0000-0000-0000-00000dad5b01') $$,
  '42501', NULL, 'AP5: cross-org audit rejected (INV-22/26)');
RESET ROLE;

-- =============================================================================
-- acknowledge_via_portal (hash-bound)
-- =============================================================================
-- AK1: wrong snapshot hash rejected
SELECT throws_ok(
  $$ SELECT public.acknowledge_via_portal('00000000-0000-0000-0000-0000dad57005', repeat('0',64)) $$,
  '42501', NULL, 'AK1: acknowledgement with unsserved snapshot hash rejected (INV-9)');

-- AK2: correct served hash acknowledges
DO $$
DECLARE v UUID;
BEGIN
  v := public.acknowledge_via_portal('00000000-0000-0000-0000-0000dad57002', repeat('e',64));
  PERFORM set_config('t.ack1', v::text, true);
END $$;
SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id='00000000-0000-0000-0000-00000dad5e02'),
  'acknowledged', 'AK2: queue → acknowledged after De Acordo');
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE type='SANCTION_ACKNOWLEDGED' AND payload->>'token_id'='00000000-0000-0000-0000-00000dad5c02'),
  1, 'AK3: SANCTION_ACKNOWLEDGED ledger fact logged (INV-3)');
-- AK4: idempotent — same token re-ack returns the same record
SELECT is(
  public.acknowledge_via_portal('00000000-0000-0000-0000-0000dad57002', repeat('e',64)),
  current_setting('t.ack1')::uuid, 'AK4: portal acknowledgement is idempotent');

-- =============================================================================
-- acknowledge_sanction_internal (authenticated TENANT_ADMIN)
-- =============================================================================
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad5b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad5a01","role":"TENANT_ADMIN"}}';
SELECT lives_ok(
  $$ SELECT public.acknowledge_sanction_internal('00000000-0000-0000-0000-00000dad5a01',
       '00000000-0000-0000-0000-00000dad5e04','00000000-0000-0000-0000-00000dad5b01','phone') $$,
  'AI1: TENANT_ADMIN records internal acknowledgement');
RESET ROLE;
SELECT is(
  (SELECT status FROM public.sanction_review_queue WHERE id='00000000-0000-0000-0000-00000dad5e04'),
  'acknowledged', 'AI2: internal ack → queue acknowledged');

-- AI3: AUDITOR cannot record internal acknowledgement (TENANT_ADMIN only)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad5b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad5a01","role":"AUDITOR"}}';
SELECT throws_ok(
  $$ SELECT public.acknowledge_sanction_internal('00000000-0000-0000-0000-00000dad5a01',
       '00000000-0000-0000-0000-00000dad5e03','00000000-0000-0000-0000-00000dad5b01','x') $$,
  '42501', NULL, 'AI3: AUDITOR cannot record internal ack');
RESET ROLE;

-- =============================================================================
-- GRANTS
-- =============================================================================
SELECT ok(
  has_function_privilege('service_role',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.create_portal_submission(uuid,text,text,bigint,text,text,text,text)','EXECUTE'),
  'GR1: create_portal_submission is service_role-only');
SELECT ok(
  has_function_privilege('anon','public.acknowledge_via_portal(uuid,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.acknowledge_via_portal(uuid,text)','EXECUTE'),
  'GR2: acknowledge_via_portal granted to anon + authenticated');

SELECT * FROM finish();
ROLLBACK;
