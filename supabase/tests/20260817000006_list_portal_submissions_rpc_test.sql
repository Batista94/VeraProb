BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- =============================================================================
-- pgTAP: list_portal_submissions — Sprint A M6
-- Covers: signature, SECURITY DEFINER, role/org gating (anti-oracle), and that
-- only PENDING_AUDIT rows of the caller's org are returned.
-- =============================================================================

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
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"D"}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad6b01', NOW()+INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (id, organization_id, queue_entry_id, created_by_user_id, expires_at_utc,
   max_access_count, token_scope, max_submissions, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad6c01','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-00000dad6b01',
   NOW()+INTERVAL '24 hours',5,'submit',5,NOW())
ON CONFLICT (id) DO NOTHING;

-- One PENDING_AUDIT submission + one QUARANTINE (must be excluded).
INSERT INTO public.portal_evidence_submissions
  (id, organization_id, queue_entry_id, token_id, quarantine_storage_path,
   file_name, mime_type_declared, file_size_bytes_declared, sha256_client, status,
   mime_type_detected, file_size_bytes_actual, sha256_server, finalized_at_utc)
VALUES
  ('00000000-0000-0000-0000-00000dad6501','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-00000dad6c01',
   '00000000-0000-0000-0000-00000dad6c01/a.pdf','a.pdf','application/pdf',2048,repeat('a',64),
   'PENDING_AUDIT','application/pdf',2048,repeat('b',64),NOW()),
  ('00000000-0000-0000-0000-00000dad6502','00000000-0000-0000-0000-00000dad6a01',
   '00000000-0000-0000-0000-00000dad6e01','00000000-0000-0000-0000-00000dad6c01',
   '00000000-0000-0000-0000-00000dad6c01/b.pdf','b.pdf','application/pdf',2048,repeat('c',64),
   'QUARANTINE',NULL,NULL,NULL,NULL)
ON CONFLICT (id) DO NOTHING;

-- S1: signature
SELECT has_function('public','list_portal_submissions',ARRAY['uuid','uuid'],
  'S1: list_portal_submissions(uuid,uuid) exists');
-- S2: SECURITY DEFINER
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname='list_portal_submissions'),
  true, 'S2: list_portal_submissions is SECURITY DEFINER');

-- HP: AUDITOR lists only PENDING_AUDIT rows of own org
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad6b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad6a01","role":"AUDITOR"}}';
SELECT is(
  (SELECT count(*)::int FROM public.list_portal_submissions(
     '00000000-0000-0000-0000-00000dad6a01','00000000-0000-0000-0000-00000dad6e01')),
  1, 'HP: only the PENDING_AUDIT submission is listed (QUARANTINE excluded)');
SELECT is(
  (SELECT submission_id FROM public.list_portal_submissions(
     '00000000-0000-0000-0000-00000dad6a01','00000000-0000-0000-0000-00000dad6e01') LIMIT 1),
  '00000000-0000-0000-0000-00000dad6501'::uuid,
  'HP2: returns the finalized submission id');
RESET ROLE;

-- B1: cross-org caller → 42501
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad6b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad6a02","role":"AUDITOR"}}';
SELECT throws_ok(
  $$ SELECT public.list_portal_submissions(
       '00000000-0000-0000-0000-00000dad6a01','00000000-0000-0000-0000-00000dad6e01') $$,
  '42501', NULL, 'B1: cross-org listing rejected (INV-22/26)');
RESET ROLE;

-- B2: non-auditor/admin role → 42501
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad6b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad6a01","role":"OPERATOR"}}';
SELECT throws_ok(
  $$ SELECT public.list_portal_submissions(
       '00000000-0000-0000-0000-00000dad6a01','00000000-0000-0000-0000-00000dad6e01') $$,
  '42501', NULL, 'B2: non-auditor role rejected');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
