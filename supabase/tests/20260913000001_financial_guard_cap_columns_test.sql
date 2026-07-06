-- =============================================================================
-- pgTAP: Financial Guard P1/6 — Stop-Loss Cap Columns
-- Migration: 20260913000001_financial_guard_cap_columns.sql
-- Plan:      forensic_records/plans/20260913000001_financial_guard_cap_columns_test_plan.md
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name)
VALUES ('f1000000-0000-0000-0000-000000000001', 'FG Cap Columns Org');

-- ── 1-3: contracts.monthly_penalty_cap_cents ────────────────────────────────
SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'contracts'
            AND column_name = 'monthly_penalty_cap_cents'),
  'contracts.monthly_penalty_cap_cents exists');

SELECT is(
  (SELECT data_type FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'contracts'
     AND column_name = 'monthly_penalty_cap_cents'),
  'bigint',
  'contracts cap column is BIGINT (INV-4 cents)');

SELECT is(
  (SELECT is_nullable FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'contracts'
     AND column_name = 'monthly_penalty_cap_cents'),
  'YES',
  'contracts cap column nullable (NULL = uncapped)');

-- ── 4-6: contract_financial_amendments.monthly_penalty_cap_cents ────────────
SELECT ok(
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'contract_financial_amendments'
            AND column_name = 'monthly_penalty_cap_cents'),
  'contract_financial_amendments.monthly_penalty_cap_cents exists');

SELECT is(
  (SELECT data_type FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'contract_financial_amendments'
     AND column_name = 'monthly_penalty_cap_cents'),
  'bigint',
  'amendments cap column is BIGINT (INV-4 cents)');

SELECT is(
  (SELECT is_nullable FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'contract_financial_amendments'
     AND column_name = 'monthly_penalty_cap_cents'),
  'YES',
  'amendments cap column nullable');

-- ── 7-10: CHECK on contracts ─────────────────────────────────────────────────
SELECT lives_ok(
  $$INSERT INTO public.contracts (id, organization_id, name, contractor_name,
      valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-00000000c001',
            'f1000000-0000-0000-0000-000000000001',
            'FG NULL cap', 'Contractor A', now(), now() + interval '1 year',
            'active', NULL)$$,
  'contract with NULL cap accepted (uncapped)');

SELECT lives_ok(
  $$INSERT INTO public.contracts (id, organization_id, name, contractor_name,
      valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-00000000c002',
            'f1000000-0000-0000-0000-000000000001',
            'FG 500k cap', 'Contractor A', now(), now() + interval '1 year',
            'active', 500000)$$,
  'contract with positive cap accepted');

SELECT throws_ok(
  $$INSERT INTO public.contracts (id, organization_id, name, contractor_name,
      valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-00000000c003',
            'f1000000-0000-0000-0000-000000000001',
            'FG zero cap', 'Contractor A', now(), now() + interval '1 year',
            'active', 0)$$,
  '23514', NULL,
  'contract cap = 0 rejected by CHECK');

SELECT throws_ok(
  $$INSERT INTO public.contracts (id, organization_id, name, contractor_name,
      valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-00000000c004',
            'f1000000-0000-0000-0000-000000000001',
            'FG negative cap', 'Contractor A', now(), now() + interval '1 year',
            'active', -1)$$,
  '23514', NULL,
  'contract cap < 0 rejected by CHECK');

-- ── 11-13: CHECK on amendments ───────────────────────────────────────────────
SELECT lives_ok(
  $$INSERT INTO public.contract_financial_amendments
      (organization_id, contract_id, financial_ceiling_cents,
       penalty_multiplier_bps, effective_at_utc, amended_by_user_id,
       monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-000000000001',
            'f1000000-0000-0000-0000-00000000c002', NULL,
            10000, now(), 'f1000000-0000-0000-0000-0000000000aa', 500000)$$,
  'amendment with positive cap accepted');

SELECT lives_ok(
  $$INSERT INTO public.contract_financial_amendments
      (organization_id, contract_id, financial_ceiling_cents,
       penalty_multiplier_bps, effective_at_utc, amended_by_user_id,
       monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-000000000001',
            'f1000000-0000-0000-0000-00000000c002', NULL,
            10000, now(), 'f1000000-0000-0000-0000-0000000000aa', NULL)$$,
  'amendment with NULL cap accepted');

SELECT throws_ok(
  $$INSERT INTO public.contract_financial_amendments
      (organization_id, contract_id, financial_ceiling_cents,
       penalty_multiplier_bps, effective_at_utc, amended_by_user_id,
       monthly_penalty_cap_cents)
    VALUES ('f1000000-0000-0000-0000-000000000001',
            'f1000000-0000-0000-0000-00000000c002', NULL,
            10000, now(), 'f1000000-0000-0000-0000-0000000000aa', 0)$$,
  '23514', NULL,
  'amendment cap = 0 rejected by CHECK');

-- ── 14: INV-3 regression — amendments still append-only ─────────────────────
SELECT throws_ok(
  $$UPDATE public.contract_financial_amendments
    SET monthly_penalty_cap_cents = 999999
    WHERE organization_id = 'f1000000-0000-0000-0000-000000000001'$$,
  'P0001', NULL,
  'amendments UPDATE still blocked by append-only trigger (INV-3)');

-- ── 15-16: constraints exist and are validated (INV-DB 3-step) ──────────────
SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_contracts_monthly_penalty_cap_positive'
            AND conrelid = 'public.contracts'::regclass
            AND convalidated),
  'chk_contracts_monthly_penalty_cap_positive exists and is validated');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_cfa_monthly_penalty_cap_positive'
            AND conrelid = 'public.contract_financial_amendments'::regclass
            AND convalidated),
  'chk_cfa_monthly_penalty_cap_positive exists and is validated');

SELECT * FROM finish();
ROLLBACK;
