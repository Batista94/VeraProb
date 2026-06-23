BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- =============================================================================
-- pgTAP: list_portal_submissions — justification_text projection (Pacote 2)
--
-- The DROP+CREATE in 20260827000002 added justification_text to the RETURNS
-- TABLE and joins dispute_evidence_attachments for attachment_id. This 1:1 test
-- proves: the new column is exposed, the carrier testimony shipped WITH a file
-- is projected, attachment_id is joined (and NULL when no file), and the
-- unchanged (uuid,uuid) signature still gates by org + role (INV-22/26).
-- Isolated namespace: dad8*.
-- =============================================================================

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
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D"}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad8b01', NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad8c01','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-00000dad8b01',
   NOW()+INTERVAL '24 hours',5,'submit',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- Submission WITH file + testimony (dad8501) and a testimony-only PENDING_AUDIT
-- submission WITHOUT an attachment row (dad8502).
INSERT INTO public.portal_evidence_submissions
  (id, organization_id, queue_entry_id, token_id, quarantine_storage_path,
   file_name, mime_type_declared, file_size_bytes_declared, sha256_client, status,
   mime_type_detected, file_size_bytes_actual, sha256_server, justification_text,
   submitted_at_utc, finalized_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad8501','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-00000dad8c01',
   '00000000-0000-0000-0000-00000dad8c01/a.jpg','a.jpg','image/jpeg',2048,repeat('a',64),
   'PENDING_AUDIT','image/jpeg',2048,repeat('b',64),
   'Defesa com anexo e texto.',NOW() - INTERVAL '2 min',NOW()),
  ('00000000-0000-0000-0000-00000dad8502','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-00000dad8c01',
   '00000000-0000-0000-0000-00000dad8c01/c.jpg','c.jpg','image/jpeg',1024,repeat('c',64),
   'PENDING_AUDIT','image/jpeg',1024,repeat('d',64),
   'Defesa somente texto.',NOW() - INTERVAL '1 min',NOW())
ON CONFLICT (id) DO NOTHING;

-- Attachment joined ONLY to the first submission.
INSERT INTO public.dispute_evidence_attachments
  (id, organization_id, queue_entry_id, submission_id, storage_path, file_name,
   mime_type, file_size_bytes, sha256_hash, uploaded_by)
VALUES
  ('00000000-0000-0000-0000-00000dad8d01','00000000-0000-0000-0000-00000dad8a01',
   '00000000-0000-0000-0000-00000dad8e01','00000000-0000-0000-0000-00000dad8501',
   '00000000-0000-0000-0000-00000dad8a01/a.jpg','a.jpg','image/jpeg',2048,repeat('b',64),
   '00000000-0000-0000-0000-00000dad8b01')
ON CONFLICT (id) DO NOTHING;

-- S1: signature unchanged (uuid, uuid)
SELECT has_function('public','list_portal_submissions',ARRAY['uuid','uuid'],
  'S1: list_portal_submissions(uuid,uuid) signature unchanged');
-- S2: the new justification_text column is part of the function result type
SELECT ok(
  pg_get_function_result('public.list_portal_submissions(uuid,uuid)'::regprocedure)
    LIKE '%justification_text text%',
  'S2: justification_text is exposed in the RETURNS TABLE');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad8b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad8a01","role":"AUDITOR"}}';

-- HP1: testimony shipped with the file is projected for the auditor.
SELECT is(
  (SELECT justification_text FROM public.list_portal_submissions(
     '00000000-0000-0000-0000-00000dad8a01','00000000-0000-0000-0000-00000dad8e01')
   WHERE submission_id = '00000000-0000-0000-0000-00000dad8501'),
  'Defesa com anexo e texto.',
  'HP1: justification_text projected with the file submission');

-- HP2: attachment_id is joined for the submission that has a file.
SELECT is(
  (SELECT attachment_id FROM public.list_portal_submissions(
     '00000000-0000-0000-0000-00000dad8a01','00000000-0000-0000-0000-00000dad8e01')
   WHERE submission_id = '00000000-0000-0000-0000-00000dad8501'),
  '00000000-0000-0000-0000-00000dad8d01'::uuid,
  'HP2: attachment_id joined for the file submission');

-- HP3: testimony-only submission has NULL attachment_id but readable text.
SELECT is(
  (SELECT attachment_id FROM public.list_portal_submissions(
     '00000000-0000-0000-0000-00000dad8a01','00000000-0000-0000-0000-00000dad8e01')
   WHERE submission_id = '00000000-0000-0000-0000-00000dad8502'),
  NULL,
  'HP3: attachment_id is NULL when no file is attached');
RESET ROLE;

-- B1: cross-org caller → 42501 (anti-oracle, INV-22/26)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad8b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad8a02","role":"AUDITOR"}}';
SELECT throws_ok(
  $$ SELECT public.list_portal_submissions(
       '00000000-0000-0000-0000-00000dad8a01','00000000-0000-0000-0000-00000dad8e01') $$,
  '42501', NULL, 'B1: cross-org listing rejected');
RESET ROLE;

-- B2: non-auditor/admin role → 42501
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad8b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad8a01","role":"OPERATOR"}}';
SELECT throws_ok(
  $$ SELECT public.list_portal_submissions(
       '00000000-0000-0000-0000-00000dad8a01','00000000-0000-0000-0000-00000dad8e01') $$,
  '42501', NULL, 'B2: non-auditor role rejected');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
