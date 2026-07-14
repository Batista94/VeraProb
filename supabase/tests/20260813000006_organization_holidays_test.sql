BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(28);

-- =============================================================================
-- organization_holidays — CIA: C
-- Quarantine Data API + tx-local GRANT for INV-22 RLS proof under quarantine
-- =============================================================================

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
  NOT has_table_privilege('authenticated', 'public.organization_holidays', 'SELECT'),
  'authenticated has no SELECT on quarantined organization_holidays');

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
SELECT is(
  public._compute_business_day_deadline(
    '00000000-0000-0000-0000-0000000d2c10', '2026-06-12'::date, 1),
  '2026-06-15 23:59:59'::timestamptz,
  'business-day deadline skips Sat/Sun (Fri +1 bday = Mon)');

SELECT is(
  public._compute_business_day_deadline(
    '00000000-0000-0000-0000-0000000d2c10', '2026-06-15'::date, 0),
  '2026-06-15 23:59:59'::timestamptz,
  'zero business days returns start-of-window end-of-day');

INSERT INTO public.organization_holidays (organization_id, holiday_date, label, is_national)
VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-06-15', 'Test Holiday', FALSE);

SELECT is(
  public._compute_business_day_deadline(
    '00000000-0000-0000-0000-0000000d2c10', '2026-06-12'::date, 1),
  '2026-06-16 23:59:59'::timestamptz,
  'business-day deadline skips an organization holiday (Mon→Tue)');

SELECT is(
  public.seed_brazilian_national_holidays('00000000-0000-0000-0000-0000000d2c11', 2026),
  12,
  'seed_brazilian_national_holidays inserts 12 national holidays');

SELECT is(
  (SELECT count(*)::int FROM public.organization_holidays
    WHERE organization_id = '00000000-0000-0000-0000-0000000d2c11' AND is_national),
  12,
  'all 12 seeded rows are flagged is_national');

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

-- ── Quarantine (20260923000001): authenticated has no Data API surface ─────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"TENANT_ADMIN"}}';

SELECT throws_ok(
  $$ SELECT count(*)::int FROM public.organization_holidays
       WHERE organization_id = '00000000-0000-0000-0000-0000000d2c11' $$,
  '42501', NULL,
  'authenticated cannot SELECT Org HB holidays (quarantined)');

SELECT throws_ok(
  $$ SELECT count(*)::int FROM public.organization_holidays
       WHERE organization_id = '00000000-0000-0000-0000-0000000d2c10' $$,
  '42501', NULL,
  'authenticated cannot SELECT own-org holidays (quarantined)');

SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-07-09', 'Admin Added') $$,
  '42501', NULL,
  'authenticated cannot INSERT holidays (quarantined)');

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"DISPATCHER"}}';
SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-07-10', 'Dispatcher') $$,
  '42501', NULL,
  'DISPATCHER cannot INSERT holidays (quarantined)');

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c11', '2026-07-11', 'Cross Org') $$,
  '42501', NULL,
  'authenticated cannot INSERT cross-org holidays (quarantined)');

RESET ROLE;

-- ── P2: tx-local GRANT for RLS proof under product quarantine (INV-22) ────────
-- Comment: tx-local grant for RLS proof under product quarantine — ROLLBACK revokes.
GRANT SELECT, INSERT ON public.organization_holidays TO authenticated;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT count(*)::int FROM public.organization_holidays
    WHERE organization_id = '00000000-0000-0000-0000-0000000d2c11'),
  0,
  'INV-22: with tx GRANT, Org A JWT sees 0 Org B holiday rows (RLS)'
);

SELECT ok(
  (SELECT count(*)::int FROM public.organization_holidays
    WHERE organization_id = '00000000-0000-0000-0000-0000000d2c10') >= 1,
  'INV-22: with tx GRANT, Org A JWT sees own holiday rows'
);

SELECT lives_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-07-09', 'Admin Added') $$,
  'INV-22: TENANT_ADMIN may INSERT own-org holiday under tx GRANT'
);

SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c11', '2026-07-11', 'Cross Org') $$,
  '42501', NULL,
  'INV-22: TENANT_ADMIN cannot INSERT cross-org holiday (RLS WITH CHECK)'
);

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000d2c10","role":"DISPATCHER"}}';
SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-0000000d2c10', '2026-07-10', 'Dispatcher') $$,
  '42501', NULL,
  'INV-22: DISPATCHER cannot INSERT (role gate on WITH CHECK)'
);

RESET ROLE;
-- ROLLBACK below drops the tx-local GRANT — production quarantine intact

SELECT * FROM finish();
ROLLBACK;
