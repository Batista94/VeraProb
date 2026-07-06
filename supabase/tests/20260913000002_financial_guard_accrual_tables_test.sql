-- =============================================================================
-- pgTAP: Financial Guard P2/6 — Accrual Accumulator + Credit Marker
-- Migration: 20260913000002_financial_guard_accrual_tables.sql
-- Plan:      forensic_records/plans/20260913000002_financial_guard_accrual_tables_test_plan.md
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name) VALUES
  ('f2000000-0000-0000-0000-00000000000a', 'FG Accrual Org A'),
  ('f2000000-0000-0000-0000-00000000000b', 'FG Accrual Org B');

INSERT INTO public.contracts (id, organization_id, name, contractor_name,
    valid_from_utc, valid_until_utc, status)
VALUES ('f2000000-0000-0000-0000-00000000c001',
        'f2000000-0000-0000-0000-00000000000a',
        'FG Accrual Contract', 'Contractor A', now(), now() + interval '1 year',
        'active');

INSERT INTO public.contract_penalty_monthly_accrual
    (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
VALUES ('f2000000-0000-0000-0000-00000000000a',
        'f2000000-0000-0000-0000-00000000c001',
        date_trunc('month', now() AT TIME ZONE 'UTC')::date, 12345, 500000);

INSERT INTO public.financial_guard_credits
    (organization_id, sanction_ledger_entry_id, credited_cents)
VALUES ('f2000000-0000-0000-0000-00000000000a',
        'f2000000-0000-0000-0000-0000000000e1', 12345);

-- ── 1-4: tables + composite PKs ──────────────────────────────────────────────
SELECT has_table('public', 'contract_penalty_monthly_accrual',
  'contract_penalty_monthly_accrual exists');
SELECT has_pk('public', 'contract_penalty_monthly_accrual',
  'accrual has PK (organization_id, contract_id, month_utc)');
SELECT has_table('public', 'financial_guard_credits',
  'financial_guard_credits exists');
SELECT has_pk('public', 'financial_guard_credits',
  'credits has PK (organization_id, sanction_ledger_entry_id)');

-- ── 5-10: exact grants (INV-DATA-API-GRANT) ──────────────────────────────────
SELECT table_privs_are('public', 'contract_penalty_monthly_accrual',
  'authenticated', ARRAY['SELECT'],
  'accrual: authenticated has SELECT only');
SELECT table_privs_are('public', 'contract_penalty_monthly_accrual',
  'anon', ARRAY[]::text[],
  'accrual: anon has nothing');
SELECT table_privs_are('public', 'contract_penalty_monthly_accrual',
  'service_role',
  ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'],
  'accrual: service_role has all privileges');
SELECT table_privs_are('public', 'financial_guard_credits',
  'authenticated', ARRAY['SELECT'],
  'credits: authenticated has SELECT only');
SELECT table_privs_are('public', 'financial_guard_credits',
  'anon', ARRAY[]::text[],
  'credits: anon has nothing');
SELECT table_privs_are('public', 'financial_guard_credits',
  'service_role',
  ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'],
  'credits: service_role has all privileges');

-- ── 11-12: RLS enabled ───────────────────────────────────────────────────────
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.contract_penalty_monthly_accrual'::regclass),
  'accrual: RLS enabled');
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE oid = 'public.financial_guard_credits'::regclass),
  'credits: RLS enabled');

-- ── 13-14: CHECK constraints ─────────────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.contract_penalty_monthly_accrual
      (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
    VALUES ('f2000000-0000-0000-0000-00000000000a',
            'f2000000-0000-0000-0000-00000000c001',
            '2030-01-01', -1, 500000)$$,
  '23514', NULL,
  'accrued_cents < 0 rejected');

SELECT throws_ok(
  $$INSERT INTO public.contract_penalty_monthly_accrual
      (organization_id, contract_id, month_utc, accrued_cents, cap_cents_snapshot)
    VALUES ('f2000000-0000-0000-0000-00000000000a',
            'f2000000-0000-0000-0000-00000000c001',
            '2030-02-01', 0, 0)$$,
  '23514', NULL,
  'cap_cents_snapshot = 0 rejected');

-- ── 15-16: tenant isolation on accrual (INV-22, scenario #7a) ────────────────
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2000000-0000-0000-0000-0000000000aa","app_metadata":{"org_id":"f2000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SET LOCAL ROLE authenticated;
SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual),
  1,
  'tenant A sees own accrual row');
RESET ROLE;

SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2000000-0000-0000-0000-0000000000bb","app_metadata":{"org_id":"f2000000-0000-0000-0000-00000000000b","role":"TENANT_ADMIN"}}';
SET LOCAL ROLE authenticated;
SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual),
  0,
  'tenant B sees zero accrual rows of A');
RESET ROLE;

-- ── 17-18: clients cannot mutate (scenario #9) ───────────────────────────────
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2000000-0000-0000-0000-0000000000aa","app_metadata":{"org_id":"f2000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$UPDATE public.contract_penalty_monthly_accrual SET accrued_cents = 0$$,
  '42501', NULL,
  'authenticated UPDATE on accrual denied (no grant)');
SELECT throws_ok(
  $$DELETE FROM public.contract_penalty_monthly_accrual$$,
  '42501', NULL,
  'authenticated DELETE on accrual denied (no grant)');
RESET ROLE;

-- ── 19-20: tenant isolation on credits ───────────────────────────────────────
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2000000-0000-0000-0000-0000000000aa","app_metadata":{"org_id":"f2000000-0000-0000-0000-00000000000a","role":"TENANT_ADMIN"}}';
SET LOCAL ROLE authenticated;
SELECT is(
  (SELECT count(*)::int FROM public.financial_guard_credits),
  1,
  'tenant A sees own credits row');
RESET ROLE;

SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f2000000-0000-0000-0000-0000000000bb","app_metadata":{"org_id":"f2000000-0000-0000-0000-00000000000b","role":"TENANT_ADMIN"}}';
SET LOCAL ROLE authenticated;
SELECT is(
  (SELECT count(*)::int FROM public.financial_guard_credits),
  0,
  'tenant B sees zero credits rows of A');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
