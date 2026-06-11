BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- ── Seeds (as postgres: bypasses RLS for fixture setup) ──────────────────────
-- Org RC (the SELECT-er) and Org B (owns a private custom code Org RC must NOT see).
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000d2c01', 'Org RC', 'Org RC SA', '00000000000d21',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rc@test.com', 'EXT_RC', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-0000000d2c02', 'Org RC-B', 'Org RC-B SA', '00000000000d22',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rcb@test.com', 'EXT_RCB', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Org B private code (distinct PK so it never collides with the global catalogue).
INSERT INTO public.dispute_reason_codes
  (code, category, label_pt, label_en, applies_to, is_custom, organization_id)
VALUES
  ('ORGB_PRIVATE', 'OTHER', 'Privado B', 'Private B', 'ALL', TRUE,
   '00000000-0000-0000-0000-0000000d2c02')
ON CONFLICT (code, organization_id) DO NOTHING;

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_table('public', 'dispute_reason_codes', 'dispute_reason_codes table exists');

SELECT has_pk('public', 'dispute_reason_codes', 'dispute_reason_codes has a primary key (code)');

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.dispute_reason_codes'::regclass),
  'RLS is enabled on dispute_reason_codes (INV-2)');

-- ── Seed catalogue ───────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.dispute_reason_codes WHERE organization_id IS NULL),
  16, 'global closed catalogue seeds exactly 16 codes (Q2)');

-- B6: industry-agnostic codes present (transport wording only in labels).
SELECT is(
  (SELECT count(*)::int FROM public.dispute_reason_codes
    WHERE code IN ('THIRD_PARTY_INCIDENT','OPERATOR_EMERGENCY',
                   'ASSET_BREAKDOWN','REGULATORY_INTERVENTION')),
  4, 'agnostic codes (B6) are seeded');

-- Category CHECK rejects an out-of-taxonomy value (defense-in-depth).
SELECT throws_ok(
  $$ INSERT INTO public.dispute_reason_codes (code, category, label_pt, label_en)
     VALUES ('BAD_CAT', 'NOPE', 'x', 'x') $$,
  '23514', NULL,
  'category CHECK rejects an unknown category');

-- ── Grants ───────────────────────────────────────────────────────────────────
SELECT ok(
  has_table_privilege('authenticated', 'public.dispute_reason_codes', 'SELECT'),
  'authenticated may SELECT dispute_reason_codes');

SELECT ok(
  NOT has_table_privilege('anon', 'public.dispute_reason_codes', 'SELECT'),
  'anon may NOT SELECT dispute_reason_codes (C6)');

SELECT ok(
  has_table_privilege('service_role', 'public.dispute_reason_codes', 'SELECT'),
  'service_role may SELECT dispute_reason_codes');

-- ── RLS behaviour (authenticated, Org RC) ────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c01","role":"TENANT_ADMIN"}}';

-- Global rows are visible to any tenant.
SELECT is(
  (SELECT count(*)::int FROM public.dispute_reason_codes WHERE organization_id IS NULL),
  16, 'authenticated tenant sees all 16 global codes (drc_select_global)');

-- Org B private code is invisible to Org RC (INV-22 tenant isolation).
SELECT is(
  (SELECT count(*)::int FROM public.dispute_reason_codes WHERE code = 'ORGB_PRIVATE'),
  0, 'Org RC cannot see Org B private reason code (INV-22)');

-- No INSERT policy → client-side creation blocked (Q2 closed catalogue).
SELECT throws_ok(
  $$ INSERT INTO public.dispute_reason_codes (code, category, label_pt, label_en, organization_id)
     VALUES ('CLIENT_MADE', 'OTHER', 'x', 'x', '00000000-0000-0000-0000-0000000d2c01') $$,
  '42501', NULL,
  'authenticated cannot INSERT a reason code (no INSERT policy, Q2)');

RESET ROLE;

-- ── Column defaults ──────────────────────────────────────────────────────────
SELECT is(
  (SELECT applies_to FROM public.dispute_reason_codes WHERE code = 'OTHER'),
  'ALL', 'applies_to defaults to ALL');

SELECT * FROM finish();
ROLLBACK;
