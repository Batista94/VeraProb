-- =============================================================================
-- pgTAP: Financial Guard P5/6 — amend_contract_financial_terms v2 (6-arg)
-- Migration: 20260913000005_financial_guard_amend_rpc.sql
-- Plan:      forensic_records/plans/20260913000005_financial_guard_amend_rpc_test_plan.md
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name) VALUES
  ('f5000000-0000-0000-0000-00000000000a', 'FG Amend Org');

INSERT INTO public.contracts (id, organization_id, name, contractor_name,
    valid_from_utc, valid_until_utc, status)
VALUES
  ('f5000000-0000-0000-0000-00000000c001', 'f5000000-0000-0000-0000-00000000000a',
   'FG A1 pre-cap fines', 'Ctr', now(), now() + interval '1 year', 'active'),
  ('f5000000-0000-0000-0000-00000000c002', 'f5000000-0000-0000-0000-00000000000a',
   'FG A2 credit epoch',  'Ctr', now(), now() + interval '1 year', 'active'),
  ('f5000000-0000-0000-0000-00000000c003', 'f5000000-0000-0000-0000-00000000000a',
   'FG A3 legacy 5-arg',  'Ctr', now(), now() + interval '1 year', 'active'),
  ('f5000000-0000-0000-0000-00000000c004', 'f5000000-0000-0000-0000-00000000000a',
   'FG A4 mid-month cut', 'Ctr', now(), now() + interval '1 year', 'active');

-- Pre-cap fines on A1 (capless passthrough — nothing accrued yet).
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES
  ('f5e00000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f5000000-0000-0000-0000-00000000c001',
   '{"verdict_evidence":{"fine_cents":30000}}'),
  ('f5e00000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f5000000-0000-0000-0000-00000000c001',
   '{"verdict_evidence":{"fine_cents":20000}}');

-- ── 1-4: signature surface ───────────────────────────────────────────────────
SELECT has_function('public', 'amend_contract_financial_terms',
  ARRAY['uuid', 'bigint', 'integer', 'timestamp with time zone', 'text', 'bigint'],
  '6-arg v2 signature exists');

SELECT ok(has_function_privilege('authenticated',
  'public.amend_contract_financial_terms(uuid, bigint, integer, timestamp with time zone, text, bigint)',
  'EXECUTE'), 'authenticated EXECUTE v2');

SELECT ok(has_function_privilege('service_role',
  'public.amend_contract_financial_terms(uuid, bigint, integer, timestamp with time zone, text, bigint)',
  'EXECUTE'), 'service_role EXECUTE v2');

SELECT is(
  (SELECT count(*)::int FROM pg_proc
   WHERE proname = 'amend_contract_financial_terms'
     AND pronamespace = 'public'::regnamespace),
  1, 'single overload (PGRST300-safe)');

-- ── 5-10: NULL→value cap with pre-existing fines seeds the accrual ───────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';

CREATE TEMP TABLE tt_a1 AS
SELECT public.amend_contract_financial_terms(
  'f5000000-0000-0000-0000-00000000c001',
  1000000, 12000, now(), 'Ativa stop-loss', 100000
) AS id;

SELECT ok((SELECT id FROM tt_a1) IS NOT NULL, 'amend with cap returns amendment UUID');

RESET ROLE;

SELECT is(
  (SELECT monthly_penalty_cap_cents FROM public.contract_financial_amendments
   WHERE id = (SELECT id FROM tt_a1)),
  100000::bigint, 'amendment row mirrors the cap (versioned SSOT)');

SELECT is(
  (SELECT monthly_penalty_cap_cents FROM public.contracts
   WHERE id = 'f5000000-0000-0000-0000-00000000c001'),
  100000::bigint, 'contracts denormalized cap synced');

SELECT is(
  (SELECT (payload ->> 'monthly_penalty_cap_cents')::bigint
   FROM public.sla_audit_ledger_v2
   WHERE type = 'CONTRACT_FINANCIAL_TERMS_AMENDED'
     AND (payload ->> 'amendment_id')::uuid = (SELECT id FROM tt_a1)),
  100000::bigint, 'ledger fact carries the cap');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c001'
     AND month_utc = (date_trunc('month', now() AT TIME ZONE 'UTC'))::date),
  50000::bigint,
  'anti-phantom-headroom: seed pre-consumes the month''s fines (30000+20000)');

SELECT is(
  (SELECT cap_cents_snapshot FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c001'),
  100000::bigint, 'seed snapshot = new cap');

-- ── 11-13: cap epoch cycle (value → NULL → value) recomputes minus credits ───
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT public.amend_contract_financial_terms(
  'f5000000-0000-0000-0000-00000000c002', NULL, 10000, now(), 'epoch 1', 100000);
RESET ROLE;

-- Guard-processed sanction + accepted dispute (credit marker recorded).
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f5e00000-0000-0000-0000-000000000003',
        'f5000000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f5000000-0000-0000-0000-00000000c002',
        '{"verdict_evidence":{"fine_cents":40000}}');

INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f5d00000-0000-0000-0000-000000000001',
        'f5000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f5e00000-0000-0000-0000-000000000003')));

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT public.amend_contract_financial_terms(
  'f5000000-0000-0000-0000-00000000c002', NULL, 10000, now(), 'remove cap', NULL);
RESET ROLE;

SELECT is(
  (SELECT monthly_penalty_cap_cents FROM public.contracts
   WHERE id = 'f5000000-0000-0000-0000-00000000c002'),
  NULL, 'explicit NULL clears the live cap');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT public.amend_contract_financial_terms(
  'f5000000-0000-0000-0000-00000000c002', NULL, 10000, now(), 'epoch 2', 200000);
RESET ROLE;

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c002'),
  0::bigint, 're-seed = fines(40000) − credits(40000) = 0 (no double count)');

SELECT is(
  (SELECT cap_cents_snapshot FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c002'),
  200000::bigint, 're-seed refreshes snapshot to new cap');

-- ── 14-16: legacy 5-arg named-compatible call (DEFAULT NULL) ─────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT lives_ok(
  $$SELECT public.amend_contract_financial_terms(
      'f5000000-0000-0000-0000-00000000c003',
      500000, 11000, now(), 'legacy call')$$,
  '5-arg call still valid (trailing DEFAULT — PGRST202-safe)');
RESET ROLE;

SELECT is(
  (SELECT monthly_penalty_cap_cents FROM public.contracts
   WHERE id = 'f5000000-0000-0000-0000-00000000c003'),
  NULL, '5-arg call leaves cap NULL');

SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c003'),
  0, 'NULL→NULL: no accrual seeded');

-- ── 17-21: #14 mid-month cap reduction below accrued ─────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT public.amend_contract_financial_terms(
  'f5000000-0000-0000-0000-00000000c004', NULL, 10000, now(), 'cap 100k', 100000);
RESET ROLE;

INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f5e00000-0000-0000-0000-000000000004',
        'f5000000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f5000000-0000-0000-0000-00000000c004',
        '{"verdict_evidence":{"fine_cents":60000}}');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT public.amend_contract_financial_terms(
  'f5000000-0000-0000-0000-00000000c004', NULL, 10000, now(), 'reduz p/ 30k', 30000);
RESET ROLE;

SELECT is(
  (SELECT monthly_penalty_cap_cents FROM public.contracts
   WHERE id = 'f5000000-0000-0000-0000-00000000c004'),
  30000::bigint, '#14 live cap reduced mid-month');

SELECT is(
  (SELECT cap_cents_snapshot FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c004'),
  100000::bigint, '#14 mid-month snapshot preserved (value→value: no re-seed)');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f5000000-0000-0000-0000-00000000c004'),
  60000::bigint, '#14 accrued untouched by reduction');

INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f5e00000-0000-0000-0000-000000000005',
        'f5000000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f5000000-0000-0000-0000-00000000c004',
        '{"verdict_evidence":{"fine_cents":5000}}');

SELECT is(
  (SELECT (payload -> 'verdict_evidence' ->> 'fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f5e00000-0000-0000-0000-000000000005'),
  0::bigint, '#14 accrued (60000) > new cap (30000): remaining 0, applied 0');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f5e00000-0000-0000-0000-000000000005'),
  true, '#14 post-reduction fine fully truncated');

-- ── 22: cap = 0 rejected ─────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"f5000000-0000-0000-0000-0000000000ad","organization_id":"f5000000-0000-0000-0000-00000000000a","app_metadata":{"org_id":"f5000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$SELECT public.amend_contract_financial_terms(
      'f5000000-0000-0000-0000-00000000c001',
      NULL, 10000, now(), 'cap zero', 0)$$,
  'P0001', 'monthly_penalty_cap_cents must be positive or NULL (INV-4)',
  'cap = 0 rejected (uncapped is NULL, never 0)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
