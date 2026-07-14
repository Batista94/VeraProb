-- =============================================================================
-- pgTAP: SLA Sandbox Schema — Phase 10.8
-- Migration: 20261001000001_sandbox_simulation_schema.sql
-- Plan: forensic_records/plans/20261001000001_sandbox_simulation_schema_test_plan.md
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'Sandbox Schema Org A'),
  ('a1000000-0000-0000-0000-000000000002', 'Sandbox Schema Org B');

-- ── 1-2: Tables exist ───────────────────────────────────────────────────────
SELECT has_table('public', 'sandbox_simulation_sessions',
  '#1 sandbox_simulation_sessions exists');
SELECT has_table('public', 'sandbox_simulation_results',
  '#2 sandbox_simulation_results exists');

-- ── 3-6: Key columns exist ──────────────────────────────────────────────────
SELECT has_column('public', 'sandbox_simulation_sessions', 'organization_id',
  '#3 sessions.organization_id exists');
SELECT has_column('public', 'sandbox_simulation_sessions', 'contract_id',
  '#4 sessions.contract_id exists');
SELECT has_column('public', 'sandbox_simulation_results', 'session_id',
  '#5 results.session_id exists');
SELECT has_column('public', 'sandbox_simulation_results', 'source_ledger_entry_id',
  '#6 results.source_ledger_entry_id exists (bare UUID, not FK)');

-- ── 7-8: RLS enabled ───────────────────────────────────────────────────────
SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'sandbox_simulation_sessions'),
  true,
  '#7 RLS enabled on sandbox_simulation_sessions');
SELECT is(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'sandbox_simulation_results'),
  true,
  '#8 RLS enabled on sandbox_simulation_results');

-- ── 9-10: CHECK constraint: period_end > period_start ───────────────────────
SELECT throws_ok(
  $$INSERT INTO public.sandbox_simulation_sessions
    (organization_id, contract_id, session_label,
     period_start_utc, period_end_utc, overrides_snapshot,
     created_by_user_id, expires_at_utc)
    VALUES ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-00000000c001', 'bad period',
            '2026-06-01'::timestamptz, '2026-05-01'::timestamptz, '{}'::jsonb,
            'a1000000-0000-0000-0000-000000000001',
            NOW() + INTERVAL '30 days')$$,
  '23514', NULL,
  '#9 chk_sandbox_period rejects end < start');

SELECT throws_ok(
  $$INSERT INTO public.sandbox_simulation_sessions
    (organization_id, contract_id, session_label,
     period_start_utc, period_end_utc, overrides_snapshot,
     created_by_user_id, expires_at_utc)
    VALUES ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-00000000c001', 'equal period',
            '2026-06-01'::timestamptz, '2026-06-01'::timestamptz, '{}'::jsonb,
            'a1000000-0000-0000-0000-000000000001',
            NOW() + INTERVAL '30 days')$$,
  '23514', NULL,
  '#10 chk_sandbox_period rejects end = start');

-- ── 11-12: CHECK constraint: max 6 months ──────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.sandbox_simulation_sessions
    (organization_id, contract_id, session_label,
     period_start_utc, period_end_utc, overrides_snapshot,
     created_by_user_id, expires_at_utc)
    VALUES ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-00000000c001', '7 months',
            '2026-01-01'::timestamptz, '2026-08-01'::timestamptz, '{}'::jsonb,
            'a1000000-0000-0000-0000-000000000001',
            NOW() + INTERVAL '30 days')$$,
  '23514', NULL,
  '#11 chk_sandbox_max_period rejects > 6 months');

-- Valid: exactly 6 months should pass
SELECT lives_ok(
  $$INSERT INTO public.sandbox_simulation_sessions
    (id, organization_id, contract_id, session_label,
     period_start_utc, period_end_utc, overrides_snapshot,
     baseline_total_fines_cents, simulated_total_fines_cents, delta_cents,
     baseline_event_count, created_by_user_id, expires_at_utc)
    VALUES ('a1000000-0000-0000-0000-aaaa00000001',
            'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-00000000c001', '6 months exact',
            '2026-01-01'::timestamptz, '2026-07-01'::timestamptz, '{}'::jsonb,
            0, 0, 0, 0,
            'a1000000-0000-0000-0000-000000000001',
            NOW() + INTERVAL '30 days')$$,
  '#12 6 months exactly is allowed');

-- ── 13-14: Immutability: UPDATE blocked ─────────────────────────────────────
SELECT throws_ok(
  $$UPDATE public.sandbox_simulation_sessions
      SET session_label = 'hacked'
    WHERE id = 'a1000000-0000-0000-0000-aaaa00000001'$$,
  '42501', NULL,
  '#13 UPDATE blocked on sessions (immutability trigger)');

-- Insert a result row for immutability test
INSERT INTO public.sandbox_simulation_results
  (id, session_id, organization_id, source_ledger_entry_id,
   source_event_type, occurred_at_utc,
   baseline_fine_cents, baseline_rule_snapshot,
   simulated_fine_cents, simulated_rule_applied, was_override_applied)
VALUES
  ('a1000000-0000-0000-0000-bbbb00000001',
   'a1000000-0000-0000-0000-aaaa00000001',
   'a1000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-cccc00000001',
   'SANCTION_RECOMMENDED', NOW(),
   30000, '{"threshold_minutes": 15}'::jsonb,
   25000, '{"threshold_minutes": 20}'::jsonb, true);

SELECT throws_ok(
  $$UPDATE public.sandbox_simulation_results
      SET simulated_fine_cents = 99999
    WHERE id = 'a1000000-0000-0000-0000-bbbb00000001'$$,
  '42501', NULL,
  '#14 UPDATE blocked on results (immutability trigger)');

-- ── 15-16: Immutability: DELETE blocked without GUC ─────────────────────────
SELECT throws_ok(
  $$DELETE FROM public.sandbox_simulation_results
    WHERE id = 'a1000000-0000-0000-0000-bbbb00000001'$$,
  '42501', NULL,
  '#15 DELETE blocked on results without GC GUC');

SELECT throws_ok(
  $$DELETE FROM public.sandbox_simulation_sessions
    WHERE id = 'a1000000-0000-0000-0000-aaaa00000001'$$,
  '42501', NULL,
  '#16 DELETE blocked on sessions without GC GUC');

-- ── 17-18: GC bypass via app.gc_sandbox GUC ─────────────────────────────────
-- Insert a new session + result to test GC path (don't use the one above, it's
-- needed for subsequent tests)
INSERT INTO public.sandbox_simulation_sessions
  (id, organization_id, contract_id, session_label,
   period_start_utc, period_end_utc, overrides_snapshot,
   baseline_total_fines_cents, simulated_total_fines_cents, delta_cents,
   baseline_event_count, created_by_user_id, expires_at_utc)
VALUES
  ('a1000000-0000-0000-0000-aaaa00000099',
   'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-00000000c001', 'GC test',
   '2026-01-01'::timestamptz, '2026-02-01'::timestamptz, '{}'::jsonb,
   0, 0, 0, 0,
   'a1000000-0000-0000-0000-000000000001',
   NOW() + INTERVAL '30 days');

SELECT set_config('app.gc_sandbox', 'true', true);

SELECT lives_ok(
  $$DELETE FROM public.sandbox_simulation_sessions
    WHERE id = 'a1000000-0000-0000-0000-aaaa00000099'$$,
  '#17 DELETE allowed on sessions with GC GUC');

SELECT set_config('app.gc_sandbox', '', true);

SELECT is(
  (SELECT count(*)::int FROM public.sandbox_simulation_sessions
   WHERE id = 'a1000000-0000-0000-0000-aaaa00000099'),
  0,
  '#18 GC-deleted session is gone');

-- ── 19-20: RLS: Tenant A cannot see Tenant B sessions ──────────────────────
-- Insert a session for Org B
INSERT INTO public.sandbox_simulation_sessions
  (id, organization_id, contract_id, session_label,
   period_start_utc, period_end_utc, overrides_snapshot,
   baseline_total_fines_cents, simulated_total_fines_cents, delta_cents,
   baseline_event_count, created_by_user_id, expires_at_utc)
VALUES
  ('a1000000-0000-0000-0000-aaaa00000002',
   'a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-00000000c001', 'Org B session',
   '2026-01-01'::timestamptz, '2026-02-01'::timestamptz, '{}'::jsonb,
   0, 0, 0, 0,
   'a1000000-0000-0000-0000-000000000002',
   NOW() + INTERVAL '30 days');

-- Set JWT as Org A
SELECT set_config('request.jwt.claims',
  '{"app_metadata": {"org_id": "a1000000-0000-0000-0000-000000000001", "role": "TENANT_ADMIN"}}',
  true);
SET ROLE authenticated;

SELECT is(
  (SELECT count(*)::int FROM public.sandbox_simulation_sessions
   WHERE organization_id = 'a1000000-0000-0000-0000-000000000002'),
  0,
  '#19 RLS: Org A cannot see Org B sessions');

SELECT is(
  (SELECT count(*)::int FROM public.sandbox_simulation_sessions
   WHERE organization_id = 'a1000000-0000-0000-0000-000000000001'),
  1,
  '#20 RLS: Org A sees own sessions');

RESET ROLE;
SELECT set_config('request.jwt.claims', '', true);

-- ── 21-22: Grants: authenticated can SELECT + INSERT ────────────────────────
SELECT ok(has_table_privilege('authenticated', 'public.sandbox_simulation_sessions', 'SELECT'),
  '#21 authenticated can SELECT sessions');
SELECT ok(has_table_privilege('authenticated', 'public.sandbox_simulation_sessions', 'INSERT'),
  '#22 authenticated can INSERT sessions');

-- ── 23-24: Grants: authenticated CANNOT UPDATE/DELETE ───────────────────────
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.sandbox_simulation_sessions', 'UPDATE'),
  '#23 authenticated cannot UPDATE sessions');
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.sandbox_simulation_sessions', 'DELETE'),
  '#24 authenticated cannot DELETE sessions');

SELECT * FROM finish();
ROLLBACK;
