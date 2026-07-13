-- =============================================================================
-- pgTAP: 20260923000001_quarantine_unused_tables
-- CIA: C — catalog privileges + runtime 42501 under authenticated session
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(30);

-- authenticated: no SELECT / INSERT on quarantined tables (catalog)
SELECT ok(NOT has_table_privilege('authenticated', 'public.audit_packages', 'SELECT'),
  'authenticated cannot SELECT audit_packages');
SELECT ok(NOT has_table_privilege('authenticated', 'public.shadow_mode_simulations', 'SELECT'),
  'authenticated cannot SELECT shadow_mode_simulations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.service_manifests', 'SELECT'),
  'authenticated cannot SELECT service_manifests');
SELECT ok(NOT has_table_privilege('authenticated', 'public.asset_status_events', 'SELECT'),
  'authenticated cannot SELECT asset_status_events');
SELECT ok(NOT has_table_privilege('authenticated', 'public.spoofing_audit_entries', 'SELECT'),
  'authenticated cannot SELECT spoofing_audit_entries');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organization_holidays', 'SELECT'),
  'authenticated cannot SELECT organization_holidays');

SELECT ok(NOT has_table_privilege('authenticated', 'public.audit_packages', 'INSERT'),
  'authenticated cannot INSERT audit_packages');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organization_holidays', 'INSERT'),
  'authenticated cannot INSERT organization_holidays');

-- anon: stripped
SELECT ok(NOT has_table_privilege('anon', 'public.audit_packages', 'SELECT'),
  'anon cannot SELECT audit_packages');
SELECT ok(NOT has_table_privilege('anon', 'public.service_manifests', 'INSERT'),
  'anon cannot INSERT service_manifests');
SELECT ok(NOT has_table_privilege('anon', 'public.spoofing_audit_entries', 'SELECT'),
  'anon cannot SELECT spoofing_audit_entries');
SELECT ok(NOT has_table_privilege('anon', 'public.organization_holidays', 'UPDATE'),
  'anon cannot UPDATE organization_holidays');

-- service_role retained (catalog)
SELECT ok(has_table_privilege('service_role', 'public.audit_packages', 'SELECT'),
  'service_role retains SELECT on audit_packages');
SELECT ok(has_table_privilege('service_role', 'public.shadow_mode_simulations', 'INSERT'),
  'service_role retains INSERT on shadow_mode_simulations');
SELECT ok(has_table_privilege('service_role', 'public.service_manifests', 'SELECT'),
  'service_role retains SELECT on service_manifests');
SELECT ok(has_table_privilege('service_role', 'public.asset_status_events', 'SELECT'),
  'service_role retains SELECT on asset_status_events');
SELECT ok(has_table_privilege('service_role', 'public.spoofing_audit_entries', 'SELECT'),
  'service_role retains SELECT on spoofing_audit_entries');
SELECT ok(has_table_privilege('service_role', 'public.organization_holidays', 'SELECT'),
  'service_role retains SELECT on organization_holidays');

-- ── Runtime attack path: authenticated session → 42501 (CIA:C) ───────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c1a1","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c1a0","role":"TENANT_ADMIN"}}';

SELECT throws_ok(
  $$ SELECT 1 FROM public.audit_packages LIMIT 1 $$,
  '42501', NULL, 'runtime: authenticated SELECT audit_packages → 42501');
SELECT throws_ok(
  $$ SELECT 1 FROM public.shadow_mode_simulations LIMIT 1 $$,
  '42501', NULL, 'runtime: authenticated SELECT shadow_mode_simulations → 42501');
SELECT throws_ok(
  $$ SELECT 1 FROM public.service_manifests LIMIT 1 $$,
  '42501', NULL, 'runtime: authenticated SELECT service_manifests → 42501');
SELECT throws_ok(
  $$ SELECT 1 FROM public.asset_status_events LIMIT 1 $$,
  '42501', NULL, 'runtime: authenticated SELECT asset_status_events → 42501');
SELECT throws_ok(
  $$ SELECT 1 FROM public.spoofing_audit_entries LIMIT 1 $$,
  '42501', NULL, 'runtime: authenticated SELECT spoofing_audit_entries → 42501');
SELECT throws_ok(
  $$ SELECT 1 FROM public.organization_holidays LIMIT 1 $$,
  '42501', NULL, 'runtime: authenticated SELECT organization_holidays → 42501');

SELECT throws_ok(
  $$ INSERT INTO public.organization_holidays (organization_id, holiday_date, label)
     VALUES ('00000000-0000-0000-0000-00000000c1a0', '2099-01-01', 'x') $$,
  '42501', NULL, 'runtime: authenticated INSERT organization_holidays → 42501');
SELECT throws_ok(
  $$ INSERT INTO public.spoofing_audit_entries
       (organization_id, device_id, window_start, window_end, risk_score,
        facts_analyzed, fact_ids, content_hash)
     VALUES (
       '00000000-0000-0000-0000-00000000c1a0', 'dev', now(), now(), 0.1,
       0, ARRAY[]::uuid[], repeat('a', 64)
     ) $$,
  '42501', NULL, 'runtime: authenticated INSERT spoofing_audit_entries → 42501');

RESET ROLE;

-- service_role can still read (admin/ops path — CIA:A operational)
SET LOCAL ROLE service_role;
SELECT lives_ok(
  $$ SELECT 1 FROM public.organization_holidays LIMIT 1 $$,
  'runtime: service_role SELECT organization_holidays lives');
SELECT lives_ok(
  $$ SELECT 1 FROM public.audit_packages LIMIT 1 $$,
  'runtime: service_role SELECT audit_packages lives');
SELECT lives_ok(
  $$ SELECT 1 FROM public.spoofing_audit_entries LIMIT 1 $$,
  'runtime: service_role SELECT spoofing_audit_entries lives');
SELECT lives_ok(
  $$ SELECT 1 FROM public.service_manifests LIMIT 1 $$,
  'runtime: service_role SELECT service_manifests lives');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
