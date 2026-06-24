BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(25);

-- ── Seeds (as postgres: bypasses RLS for fixture setup) ──────────────────────
-- Org: dual-control ON at 100000 cents, TTL 48h.
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains, dual_control_threshold_cents, dual_control_ttl_hours
) VALUES
  ('00000000-0000-0000-0000-0000000d2c40', 'Org TAX', 'Org TAX SA', '00000000000d80',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'tax@test.com', 'EXT_TAX', 'LOGISTICS', ARRAY['test.com'], 100000, 48)
ON CONFLICT (id) DO NOTHING;

-- Contract: no dual-control override (inherits org baseline 100000).
INSERT INTO public.contracts
  (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, status)
VALUES
  ('11111111-1111-1111-1111-1111111111c0', '00000000-0000-0000-0000-0000000d2c40',
   'C-TAX', 'K', now(), now() + INTERVAL '1 year', 'active')
ON CONFLICT (id) DO NOTHING;

-- An INACTIVE global reason code (taxonomy must reject inactive, even if it exists).
INSERT INTO public.dispute_reason_codes (code, category, label_pt, label_en, applies_to, is_active)
VALUES ('INACTIVE_TEST', 'OTHER', 'Inativo', 'Inactive', 'ALL', FALSE)
ON CONFLICT (code, organization_id) DO NOTHING;

-- Queue entries. fine_cents lives in the sealed verdict_evidence (INV-15).
-- A: accept TERMINAL (fine <= threshold). O: overturn FORK (fine > threshold).
-- P: accept FORK (confirm path). R: retract. M: blocked by MISMATCH evidence.
-- J: reject terminal (valid). JI: reject invalid-code (throws, no mutation).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, disputed_at, disputed_by)
VALUES
  ('00000000-0000-0000-0000-0000000d2ca1', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-accept', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 50000}'::jsonb, 'disputed', '2026-08-10T00:00:00Z',
   '00000000-0000-0000-0000-0000000db0a1'),
  ('00000000-0000-0000-0000-0000000d2ca2', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-overturn', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 200000}'::jsonb, 'disputed', '2026-08-10T00:00:00Z',
   '00000000-0000-0000-0000-0000000db0a2'),
  ('00000000-0000-0000-0000-0000000d2ca7', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-acc-fork', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 200000}'::jsonb, 'disputed', '2026-08-10T00:00:00Z',
   '00000000-0000-0000-0000-0000000db0a7'),
  ('00000000-0000-0000-0000-0000000d2ca3', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-retract', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 50000}'::jsonb, 'disputed', '2026-08-10T00:00:00Z',
   '00000000-0000-0000-0000-0000000db0c3'),
  ('00000000-0000-0000-0000-0000000d2ca4', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-mismatch', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 50000}'::jsonb, 'disputed', '2026-08-10T00:00:00Z',
   '00000000-0000-0000-0000-0000000db0c4'),
  ('00000000-0000-0000-0000-0000000d2ca5', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-reject', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 50000}'::jsonb, 'pending', NULL, NULL),
  ('00000000-0000-0000-0000-0000000d2ca6', '00000000-0000-0000-0000-0000000d2c40',
   gen_random_uuid(), 'set-reject-bad', '11111111-1111-1111-1111-1111111111c0',
   '{"fine_cents": 50000}'::jsonb, 'pending', NULL, NULL);

-- MISMATCH evidence on M → resolution must be blocked (B2).
INSERT INTO public.dispute_evidence_attachments
  (organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, verification_status, uploaded_by)
VALUES
  ('00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca4',
   'evid/m1.pdf', 'm1.pdf', 'application/pdf', 1024,
   'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
   'MISMATCH', '00000000-0000-0000-0000-0000000db0c4');

-- Rule set required by _persist_evidence_snapshot (wired to reject/resolve/peer RPCs in 20260824000001).
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('11111111-1111-1111-1111-1111111100bb',
        '00000000-0000-0000-0000-0000000d2c40',
        '11111111-1111-1111-1111-1111111111c0')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, created_at_utc)
VALUES ('11111111-1111-1111-1111-1111111100cc',
        '11111111-1111-1111-1111-1111111100bb',
        'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

-- ── B1: signatures (new exist, old dropped) ──────────────────────────────────
SELECT has_function('public', 'resolve_dispute',
  ARRAY['uuid','uuid','text','text','uuid','text','timestamp with time zone','text','text'],
  'resolve_dispute exists with the 9-param taxonomy signature');
SELECT hasnt_function('public', 'resolve_dispute',
  ARRAY['uuid','uuid','text','text','uuid','text','timestamp with time zone','text'],
  'old 8-param resolve_dispute is dropped (no unprotected overload)');
SELECT has_function('public', 'reject_sanction',
  ARRAY['uuid','uuid','uuid','text','text','text','timestamp with time zone'],
  'reject_sanction exists with the 7-param taxonomy signature');
SELECT hasnt_function('public', 'reject_sanction',
  ARRAY['uuid','uuid','uuid','text','text','timestamp with time zone'],
  'old 6-param reject_sanction is dropped (no unprotected overload)');
SELECT ok(
  has_function_privilege('authenticated',
    'public.resolve_dispute(uuid, uuid, text, text, uuid, text, timestamp with time zone, text, text)',
    'EXECUTE'),
  'authenticated may execute the new resolve_dispute');
SELECT ok(
  has_function_privilege('authenticated',
    'public.reject_sanction(uuid, uuid, uuid, text, text, text, timestamp with time zone)',
    'EXECUTE'),
  'authenticated may execute the new reject_sanction');

-- ── Auditor 1 (AUDITOR Org TAX, sub ...0dbaa1) ────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000dbaa1","organization_id":"00000000-0000-0000-0000-0000000d2c40","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c40","role":"AUDITOR"}}';

-- ── Taxonomy validation (Q2 / D6 / D7) — all throw before mutating A ──────────
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca1',
       'DISPUTE_ACCEPTED', 'reason', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:00:00Z', 'idem-bad1', 'NONEXISTENT_CODE') $$,
  '42501', NULL,
  'accept with an unknown reason_code is rejected (anti-oracle 42501)');
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca1',
       'DISPUTE_ACCEPTED', 'reason', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:00:00Z', 'idem-bad2', 'INACTIVE_TEST') $$,
  '42501', NULL,
  'accept with an INACTIVE reason_code is rejected (42501)');
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca1',
       'DISPUTE_OVERTURNED', 'reason', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:00:00Z', 'idem-bad3', NULL) $$,
  '42501', NULL,
  'overturn with a NULL reason_code is rejected (42501)');

-- ── B2: a verdict can NEVER seal over MISMATCH evidence (D5e) ─────────────────
SELECT throws_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca4',
       'DISPUTE_ACCEPTED', 'reason', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:00:00Z', 'idem-mm', 'FORCE_MAJEURE') $$,
  '42501', NULL,
  'accept is blocked while tampered (MISMATCH) evidence is attached (B2)');

-- ── Accept TERMINAL with valid taxonomy (D8) ─────────────────────────────────
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca1',
       'DISPUTE_ACCEPTED', 'GPS trace exonerates.', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:01:00Z', 'idem-acc', 'FORCE_MAJEURE') $$,
  'below-threshold accept with a valid reason_code goes terminal');
SELECT is(
  (SELECT payload ->> 'reason_code' FROM public.sla_audit_ledger_v2
     WHERE type = 'DISPUTE_ACCEPTED'
       AND payload ->> 'queue_entry_id' = '00000000-0000-0000-0000-0000000d2ca1'),
  'FORCE_MAJEURE', 'DISPUTE_ACCEPTED fact embeds the reason_code (INV-15)');
SELECT is(
  (SELECT status || ':' || resolution_reason_code FROM public.sanction_review_queue
     WHERE id = '00000000-0000-0000-0000-0000000d2ca1'),
  'rejected:FORCE_MAJEURE', 'accept flips queue to rejected + stamps resolution_reason_code');

-- ── Dual-control PRESERVED: overturn above threshold forks (B1 / D7b) ────────
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca2',
       'DISPUTE_OVERTURNED', 'Enforce.', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:02:00Z', 'idem-ovr', 'CONTRACT_EXCEPTION') $$,
  'high-value overturn still forks into peer review (dual-control preserved)');
SELECT is(
  (SELECT status || ':' || peer_review_proposed_action || ':' || peer_review_reason_code
     FROM public.sanction_review_queue WHERE id = '00000000-0000-0000-0000-0000000d2ca2'),
  'pending_peer_review:OVERTURN:CONTRACT_EXCEPTION',
  'overturn fork holds the reason_code through the peer-review hold (Senior F5)');

-- ── Accept FORK then confirm embeds reason_code on the terminal fact (D7c) ────
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca7',
       'DISPUTE_ACCEPTED', 'Waive.', '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:03:00Z', 'idem-accfork', 'SENSOR_FAULT') $$,
  'high-value accept forks into peer review');

-- Distinct second auditor (sub ...0dbaa2) confirms the DISPUTE_ACCEPT fork.
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000dbaa2","organization_id":"00000000-0000-0000-0000-0000000d2c40","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c40","role":"AUDITOR"}}';
SELECT lives_ok(
  $$ SELECT public.confirm_peer_review(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca7',
       '00000000-0000-0000-0000-0000000dbaa2', 'a2@test.com',
       '2026-08-13T12:04:00Z', 'idem-confirm') $$,
  'distinct second auditor confirms the accept fork');
SELECT is(
  (SELECT payload ->> 'reason_code' || ':' || (payload ->> 'second_reviewer_id')
     FROM public.sla_audit_ledger_v2
     WHERE type = 'DISPUTE_ACCEPTED'
       AND payload ->> 'queue_entry_id' = '00000000-0000-0000-0000-0000000d2ca7'),
  'SENSOR_FAULT:00000000-0000-0000-0000-0000000dbaa2',
  'confirm seals the terminal fact with the threaded reason_code + 2nd signature');

-- ── Retract preserves provenance (INV-23 / D9 / D10) ─────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000dbaa1","organization_id":"00000000-0000-0000-0000-0000000d2c40","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c40","role":"AUDITOR"}}';
SELECT lives_ok(
  $$ SELECT public.resolve_dispute(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca3',
       'DISPUTE_RETRACTED', NULL, '00000000-0000-0000-0000-0000000dbaa1',
       'a1@test.com', '2026-08-13T12:05:00Z', 'idem-retract', NULL) $$,
  'retract succeeds without a reason_code (not financially effective)');
SELECT is(
  (SELECT status || ':' || COALESCE(disputed_by::text, '') FROM public.sanction_review_queue
     WHERE id = '00000000-0000-0000-0000-0000000d2ca3'),
  'pending:',
  'retract returns to pending and clears disputed_by to prevent state leak');
SELECT is(
  (SELECT (payload ->> 'original_disputed_by') || ':' || (payload ->> 'retracted_by_user_id')
     FROM public.sla_audit_ledger_v2
     WHERE type = 'DISPUTE_RETRACTED'
       AND payload ->> 'queue_entry_id' = '00000000-0000-0000-0000-0000000d2ca3'),
  '00000000-0000-0000-0000-0000000db0c3:00000000-0000-0000-0000-0000000dbaa1',
  'retract fact records who opened AND who retracted (INV-23 provenance)');

-- ── reject_sanction taxonomy (7-param) ───────────────────────────────────────
SELECT throws_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca6',
       '00000000-0000-0000-0000-0000000dbaa1', 'a1@test.com',
       'reason', 'NONEXISTENT_CODE', '2026-08-13T12:06:00Z') $$,
  '42501', NULL,
  'reject with an unknown reason_code is rejected (42501)');
SELECT lives_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-0000000d2c40', '00000000-0000-0000-0000-0000000d2ca5',
       '00000000-0000-0000-0000-0000000dbaa1', 'a1@test.com',
       'Carrier GPS confirms on-route.', 'FORCE_MAJEURE', '2026-08-13T12:07:00Z') $$,
  'below-threshold reject with a valid reason_code goes terminal');
SELECT is(
  (SELECT status || ':' || rejection_reason_code FROM public.sanction_review_queue
     WHERE id = '00000000-0000-0000-0000-0000000d2ca5'),
  'rejected:FORCE_MAJEURE', 'reject flips queue to rejected + stamps rejection_reason_code');
SELECT is(
  (SELECT payload ->> 'reason_code' FROM public.sla_audit_ledger_v2
     WHERE type = 'VERDICT_REFUSED'
       AND payload ->> 'queue_entry_id' = '00000000-0000-0000-0000-0000000d2ca5'),
  'FORCE_MAJEURE', 'VERDICT_REFUSED fact embeds the reason_code');

SELECT * FROM finish();
ROLLBACK;
