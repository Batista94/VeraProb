BEGIN;
SELECT plan(6);

-- 1. Verify that the test-only function was created and properly restricted
SELECT has_function(
  'public',
  'test_hold_financial_guard_lock',
  ARRAY['uuid', 'uuid', 'integer'],
  'test_hold_financial_guard_lock function should exist'
);

SELECT function_privs_are(
  'public',
  'test_hold_financial_guard_lock',
  ARRAY['uuid', 'uuid', 'integer'],
  'public',
  ARRAY[]::TEXT[],
  'PUBLIC should not have privileges on test_hold_financial_guard_lock'
);

-- Prepare dummy org and contract
INSERT INTO public.organizations (id, name) VALUES 
  ('00000000-0000-0000-0000-000000000123', 'Test Org') ON CONFLICT DO NOTHING;

INSERT INTO public.contracts (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, monthly_penalty_cap_cents, status) VALUES 
  ('11111111-1111-1111-1111-111111111123', '00000000-0000-0000-0000-000000000123', 'Test Contract', 'Contractor', '2020-01-01', '2030-01-01', 10000, 'active') ON CONFLICT DO NOTHING;

-- Simulate the old bug: a row was inserted with a massive fine, bypassing the cap (e.g. legacy deferred row)
ALTER TABLE public.sla_audit_ledger_v2 DISABLE TRIGGER trg_financial_guard;

INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, contract_id, occurred_at_utc, payload) VALUES 
  ('00000000-0000-0000-0000-000000000123', 'SANCTION_RECOMMENDED', '11111111-1111-1111-1111-111111111123', now(), '{"verdict_evidence": {"fine_cents": 15000}, "cap_check_deferred": true}');

ALTER TABLE public.sla_audit_ledger_v2 ENABLE TRIGGER trg_financial_guard;

-- Set accrued to 0 so reconcile corrects it and logs drift
UPDATE public.contract_penalty_monthly_accrual 
  SET accrued_cents = 0 
WHERE organization_id = '00000000-0000-0000-0000-000000000123' AND contract_id = '11111111-1111-1111-1111-111111111123';

-- Run the reconcile function
SELECT public.reconcile_financial_guard('00000000-0000-0000-0000-000000000123');

-- Check if accrued_cents was clamped to monthly_penalty_cap_cents (10000) instead of 13000
SELECT results_eq(
  $$ SELECT accrued_cents FROM public.contract_penalty_monthly_accrual WHERE organization_id = '00000000-0000-0000-0000-000000000123' AND contract_id = '11111111-1111-1111-1111-111111111123' $$,
  $$ VALUES (10000::bigint) $$,
  'reconcile_financial_guard should clamp accrued_cents to the monthly cap'
);

-- Check if the system audit log recorded the drift with overshoot_clamped = true
SELECT isnt_empty(
  $$ SELECT 1 FROM public.system_audit_log WHERE event_type = 'FINANCIAL_GUARD_DRIFT' AND organization_id = '00000000-0000-0000-0000-000000000123' AND payload->>'overshoot_clamped' = 'true' $$,
  'System audit log should record FINANCIAL_GUARD_DRIFT with overshoot_clamped=true when clamping'
);

-- Verify expected_cents in the payload was the capped value (10000)
SELECT results_eq(
  $$ SELECT (payload->>'expected_cents')::bigint FROM public.system_audit_log WHERE event_type = 'FINANCIAL_GUARD_DRIFT' AND organization_id = '00000000-0000-0000-0000-000000000123' AND payload->>'overshoot_clamped' = 'true' LIMIT 1 $$,
  $$ VALUES (10000::bigint) $$,
  'System audit log drift payload should have expected_cents equal to the cap'
);

-- Verify expected behavior without clamp: insert an independent small sanction under a different contract
INSERT INTO public.contracts (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, monthly_penalty_cap_cents, status) VALUES 
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000123', 'Test Contract 2', 'Contractor 2', '2020-01-01', '2030-01-01', 10000, 'active') ON CONFLICT DO NOTHING;

INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, contract_id, occurred_at_utc, payload) VALUES 
  ('00000000-0000-0000-0000-000000000123', 'SANCTION_RECOMMENDED', '22222222-2222-2222-2222-222222222222', now(), '{"verdict_evidence": {"fine_cents": 3000}}');

SELECT public.reconcile_financial_guard('00000000-0000-0000-0000-000000000123');

SELECT results_eq(
  $$ SELECT accrued_cents FROM public.contract_penalty_monthly_accrual WHERE organization_id = '00000000-0000-0000-0000-000000000123' AND contract_id = '22222222-2222-2222-2222-222222222222' $$,
  $$ VALUES (3000::bigint) $$,
  'reconcile_financial_guard should set accrued_cents to exact value when under the cap'
);

SELECT * FROM finish();
ROLLBACK;
