BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(23);

-- ── Seeds (as postgres: bypasses RLS for fixture setup) ──────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000d2c10', 'Org HA', 'Org HA SA', '00000000000d30',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'ha@test.com', 'EXT_HA', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-0000000d2c11', 'Org HB', 'Org HB SA', '00000000000d31',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'hb@test.com', 'EXT_HB', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_table('public', 'organization_holidays', 'organization_holidays table exists');

SELECT has_pk('public', 'organization_holidays', 'organization_holidays has a primary key');

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.organization_holidays'::regclass),
  'RLS is enabled on organization_holidays (INV-2)');

SELECT ok(
  (SELECT count(*)::int FROM pg_constraint WHERE conname = 'uq_org_holiday_date') = 1,
  'uq_org_holiday_date UNIQUE (organization_id, holiday_date) exists');

SELECT has_column('public', 'organization_holidays', 'deleted_at',
  'soft-delete column deleted_at exists (M-arch)');

-- ── Grants (INV-DATA-API-GRANT + M-arch: no client DELETE) ───────────────────
SELECT ok(
  has_table_privilege('authenticated', 'public.organization_holidays', 'SELECT'),
  'authenticated may SELECT organization_holidays');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.organization_holidays', 'DELETE'),
  'authenticated may NOT DELETE (M-arch: soft-delete only)');

SELECT ok(
  has_table_privilege('service_role', 'public.organization_holidays', 'DELETE'),
  'service_role has ALL (incl. DELETE) on organization_holidays');

SELECT ok(
  NOT has_table_privilege('anon', 'public.organization_holidays', 'SELECT'),
  'anon may NOT SELECT organization_holidays');

-- ── Easter (Anonymous Gregorian) — verified anchor 2026 = Apr 5 ───────────────
SELECT is(
  public._compute_easter(2026),
  '2026-04-05'::date,
  '_compute_easter(2026) returns Apr 5 (verified anchor)');

-- ── Business-day deadline: weekend skip (Fri Jun 12 +1 bday → Mon Jun 15) ─────
-- OrgHA has no holidays yet in this window.
SELECT is(
  public._compute_business_day_deadline(
    '00000000-0000-0000-0000-0000000d2c10', '2026-06-12'::date, 1),
  '2026-06-15 23:59:59'::timestamptz,
  'business-day deadline skips Sat/Sun (Fri +1 bday = Mon)');

-- ── Business-day deadline: zero/negative business days → same day end-of-day ──
SELECT is(
  public._compute_business_day_deadline(
    '00000000-0000-0000-0000-0000000d2c10', '2026-06-15'::date, 0),
  '2026-06-15 23:59:59'::timestamptz,
  'zero business days returns start-of-window end-of-day');

-- ── Business-day deadline: holiday skip (Mon Jun 15 is a holiday → Tue Jun 16) ─
INSERT INTO public.organization_holidays (organization_id, holiday_date, label, is_national)
VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-06-15', 'Test Holiday', FALSE);

SELECT is(
  public._compute_business_day_deadline(
    '00000000-0000-0000-0000-0000000d2c10', '2026-06-12'::date, 1),
  '2026-06-16 23:59:59'::timestamptz,
  'business-day deadline skips an organization holiday (Mon→Tue)');

-- ── Locale pack: BR national holidays seed (run on OrgHB, isolated) ───────────
SELECT is(
  public.seed_brazilian_national_holidays('00000000-0000-0000-0000-0000000d2c11', 2026),
  12,
  'seed_brazilian_national_holidays inserts 12 national holidays');

SELECT is(
  (SELECT count(*)::int FROM public.organization_holidays
    WHERE organization_id = '00000000-0000-0000-0000-0000000d2c11' AND is_national),
  12,
  'all 12 seeded rows are flagged is_national');

-- ── H4: locale pack is NEVER reachable by generic tenant provisioning ─────────
SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'public.seed_brazilian_national_holidays(uuid, integer)', 'EXECUTE'),
  'authenticated cannot EXECUTE the locale-pack seed (H4)');

SELECT ok(
  has_function_privilege(
    'service_role', 'public.seed_brazilian_national_holidays(uuid, integer)', 'EXECUTE'),
  'service_role may EXECUTE the locale-pack seed (explicit invocation only)');

SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'public._compute_business_day_deadline(uuid, date, integer)', 'EXECUTE'),
  'authenticated cannot EXECUTE the internal deadline function');

-- ── RLS behaviour (authenticated, Org HA) ────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"TENANT_ADMIN"}}';

-- Org HB holidays (seeded above) are invisible to Org HA (INV-22).
SELECT is(
  (SELECT count(*)::int FROM public.organization_holidays
    WHERE organization_id = '00000000-0000-0000-0000-0000000d2c11'),
  0, 'Org HA cannot see Org HB holidays (INV-22)');

-- Org HA sees its own holiday row.
SELECT is(
  (SELECT count(*)::int FROM public.organization_holidays
    WHERE organization_id = '00000000-0000-0000-0000-0000000d2c10'),
  1, 'Org HA sees its own holiday (oh_select_own_org)');

-- TENANT_ADMIN may INSERT a holiday for its own org.
SELECT lives_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-07-09', 'Admin Added') $$,
  'TENANT_ADMIN may INSERT a holiday for its own org');

-- A non-admin (DISPATCHER) cannot INSERT (oh_insert_own_org requires TENANT_ADMIN).
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"DISPATCHER"}}';
SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-07-10', 'Dispatcher') $$,
  '42501', NULL,
  'non-admin (DISPATCHER) cannot INSERT a holiday');

-- Cross-org INSERT is blocked even for a TENANT_ADMIN (INV-22).
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c11', '2026-07-11', 'Cross Org') $$,
  '42501', NULL,
  'TENANT_ADMIN cannot INSERT a holiday for another org (INV-22)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
