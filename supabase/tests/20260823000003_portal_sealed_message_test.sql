-- Coverage for 20260823000003_portal_sealed_message.sql
-- read_dispute_portal returns the sealed "JUDGED_INTERNALLY" closure when a
-- token is revoked AND its sanction reached a terminal verdict; preserves the
-- generic deny for revoked-but-non-terminal and for forged tokens (anti-oracle).
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES ('dddddddd-0000-0000-0000-000000000001', 'Org Sealed', '00000000sd0001', NOW())
ON CONFLICT (id) DO NOTHING;

-- E1: terminally applied sanction (verdict sealed internally).
-- E2: still disputed (admin-revoked token, NOT judged).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('dddddddd-0000-0000-0000-0000000000e1', 'dddddddd-0000-0000-0000-000000000001',
   'dddddddd-0000-0000-0000-0000000000f1', 'set-sealed',
   'dddddddd-0000-0000-0000-0000000000aa',
   '{"rule_type":"NO_SHOW_PENALTY","description":"Falta comprovada","fine_cents":50000}'::jsonb,
   'applied', NOW(), 'dddddddd-0000-0000-0000-0000000000b1', NOW() + INTERVAL '5 days'),
  ('dddddddd-0000-0000-0000-0000000000e2', 'dddddddd-0000-0000-0000-000000000001',
   'dddddddd-0000-0000-0000-0000000000f2', 'set-disputed',
   'dddddddd-0000-0000-0000-0000000000aa',
   '{"rule_type":"NO_SHOW_PENALTY","description":"Em disputa","fine_cents":50000}'::jsonb,
   'disputed', NOW(), 'dddddddd-0000-0000-0000-0000000000b1', NOW() + INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

-- Revoked token over the SEALED sanction (mirrors VERDICT_SEALED revocation).
INSERT INTO public.dispute_portal_tokens
  (organization_id, queue_entry_id, created_by_user_id, expires_at_utc,
   max_access_count, revoked_at_utc, revoked_reason)
VALUES
  ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-0000000000e1',
   'dddddddd-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5,
   NOW(), 'VERDICT_SEALED');

-- Revoked token over a STILL-DISPUTED sanction (e.g. admin revocation).
INSERT INTO public.dispute_portal_tokens
  (organization_id, queue_entry_id, created_by_user_id, expires_at_utc,
   max_access_count, revoked_at_utc)
VALUES
  ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-0000000000e2',
   'dddddddd-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5,
   NOW());

CREATE TEMP TABLE _sealed_tok AS
  SELECT token FROM public.dispute_portal_tokens
   WHERE queue_entry_id = 'dddddddd-0000-0000-0000-0000000000e1' LIMIT 1;
CREATE TEMP TABLE _disp_tok AS
  SELECT token FROM public.dispute_portal_tokens
   WHERE queue_entry_id = 'dddddddd-0000-0000-0000-0000000000e2' LIMIT 1;

-- T1: sealed + terminal → closed payload (no exception).
SELECT lives_ok(
  $$ SELECT public.read_dispute_portal(token) FROM _sealed_tok $$,
  'T1: revoked token on terminal sanction returns a payload (no deny)');

-- T2: payload carries closed = true.
SELECT is(
  (SELECT (public.read_dispute_portal(token) ->> 'closed') FROM _sealed_tok),
  'true', 'T2: sealed response sets closed = true');

-- T3: closed_reason = JUDGED_INTERNALLY.
SELECT is(
  (SELECT (public.read_dispute_portal(token) ->> 'closed_reason') FROM _sealed_tok),
  'JUDGED_INTERNALLY', 'T3: closed_reason == JUDGED_INTERNALLY');

-- T4: terminal status surfaced for the banner.
SELECT is(
  (SELECT (public.read_dispute_portal(token) -> 'dispute_summary' ->> 'status') FROM _sealed_tok),
  'applied', 'T4: dispute_summary.status == applied');

-- T5: revoked-but-still-disputed → generic deny (no oracle).
SELECT throws_ok(
  $$ SELECT public.read_dispute_portal(token) FROM _disp_tok $$,
  '42501', 'Portal access denied.',
  'T5: revoked non-terminal token keeps the generic deny');

-- T6: forged/unknown token → generic deny (unchanged).
SELECT throws_ok(
  $$ SELECT public.read_dispute_portal('00000000-0000-0000-0000-0000000000ff'::uuid) $$,
  '42501', 'Portal access denied.',
  'T6: unknown token denied generically');

SELECT * FROM finish();
ROLLBACK;
