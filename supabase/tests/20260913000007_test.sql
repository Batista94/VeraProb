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

-- Prepare dummy org and a CAPLESS contract.
-- We reproduce the legacy overshoot (a full fine booked without accrual)
-- WITHOUT toggling triggers on the partitioned parent. `ALTER TABLE
-- sla_audit_ledger_v2 DISABLE/ENABLE TRIGGER` segfaults local PG inside a
-- transaction (see reference_local_pg_segfaults #2) — instead we insert while
-- the contract is capless (guard passthrough leaves the full fine, no accrual)
-- and impose the cap afterwards.
INSERT INTO public.organizations (id, name) VALUES
  ('00000000-0000-0000-0000-000000000123', 'Test Org') ON CONFLICT DO NOTHING;

INSERT INTO public.contracts (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, monthly_penalty_cap_cents, status) VALUES
  ('11111111-1111-1111-1111-111111111123', '00000000-0000-0000-0000-000000000123', 'Test Contract', 'Contractor', '2020-01-01', '2030-01-01', NULL, 'active') ON CONFLICT DO NOTHING;

-- Guard passthrough (contract capless) → full 15000 fine booked, no accrual row.
INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, contract_id, occurred_at_utc, payload) VALUES
  ('00000000-0000-0000-0000-000000000123', 'SANCTION_RECOMMENDED', '11111111-1111-1111-1111-111111111123', now(), '{"verdict_evidence": {"fine_cents": 15000}}');

-- Impose the cap AFTER the legacy fine is booked.
UPDATE public.contracts SET monthly_penalty_cap_cents = 10000
 WHERE id = '11111111-1111-1111-1111-111111111123';

-- Run the reconcile function
SELECT public.reconcile_financial_guard('00000000-0000-0000-0000-000000000123');

-- Check if accrued_cents was clamped to monthly_penalty_cap_cents (10000) instead of 15000
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

-- Under-cap path (no clamp): a second capless contract booked below the cap.
INSERT INTO public.contracts (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc, monthly_penalty_cap_cents, status) VALUES
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000123', 'Test Contract 2', 'Contractor 2', '2020-01-01', '2030-01-01', NULL, 'active') ON CONFLICT DO NOTHING;

INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, contract_id, occurred_at_utc, payload) VALUES
  ('00000000-0000-0000-0000-000000000123', 'SANCTION_RECOMMENDED', '22222222-2222-2222-2222-222222222222', now(), '{"verdict_evidence": {"fine_cents": 3000}}');

UPDATE public.contracts SET monthly_penalty_cap_cents = 10000
 WHERE id = '22222222-2222-2222-2222-222222222222';

SELECT public.reconcile_financial_guard('00000000-0000-0000-0000-000000000123');

SELECT results_eq(
  $$ SELECT accrued_cents FROM public.contract_penalty_monthly_accrual WHERE organization_id = '00000000-0000-0000-0000-000000000123' AND contract_id = '22222222-2222-2222-2222-222222222222' $$,
  $$ VALUES (3000::bigint) $$,
  'reconcile_financial_guard should set accrued_cents to exact value when under the cap'
);

SELECT * FROM finish();
ROLLBACK;
