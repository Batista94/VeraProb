-- =============================================================================
-- pgTAP: SLA Sandbox Simulation Engine — Phase 10.8
-- Migration: 20261001000002_sandbox_simulation_engine.sql
-- Plan: forensic_records/plans/20261001000002_sandbox_simulation_engine_test_plan.md
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name) VALUES
  ('b2000000-0000-0000-0000-000000000001', 'Sandbox Engine Org A'),
  ('b2000000-0000-0000-0000-000000000002', 'Sandbox Engine Org B');

INSERT INTO public.contracts
  (id, organization_id, name, contractor_name,
   valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
VALUES
  ('b2000000-0000-0000-0000-00000000c001',
   'b2000000-0000-0000-0000-000000000001',
   'Sandbox Test Contract', 'Carrier A',
   '2025-01-01'::timestamptz, '2027-12-31'::timestamptz,
   'active', 100000),  -- cap 1000.00
  ('b2000000-0000-0000-0000-00000000c002',
   'b2000000-0000-0000-0000-000000000001',
   'Sandbox Uncapped Contract', 'Carrier B',
   '2025-01-01'::timestamptz, '2027-12-31'::timestamptz,
   'active', NULL);     -- no cap

-- Rule set + rule version for temporal lookup
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('b2000000-0000-0000-0000-00000000f001',
        'b2000000-0000-0000-0000-000000000001',
        'b2000000-0000-0000-0000-00000000c001');

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, is_scheduled, created_at_utc)
VALUES
  ('b2000000-0000-0000-0000-00000000f002',
   'b2000000-0000-0000-0000-00000000f001',
   'MAX_TOLERANCE_DELAY',
   '{"threshold_minutes": 15}'::jsonb, 1, 1,
   '2025-01-01'::timestamptz, NULL, false, '2025-01-01'::timestamptz);

-- Seed 3 penal ledger events for the simulation period
INSERT INTO public.sla_audit_ledger_v2
  (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES
  ('b2000000-0000-0000-0000-00000000e001',
   'b2000000-0000-0000-0000-000000000001',
   '2026-03-15 10:00:00+00'::timestamptz,
   'SANCTION_RECOMMENDED',
   'b2000000-0000-0000-0000-00000000c001',
   '{"reason_code":"RC1","verdict_evidence":{"fine_cents":20000,"rule_type":"MAX_TOLERANCE_DELAY"}}'::jsonb),
  ('b2000000-0000-0000-0000-00000000e002',
   'b2000000-0000-0000-0000-000000000001',
   '2026-04-10 14:30:00+00'::timestamptz,
   'NO_SHOW_PENALTY',
   'b2000000-0000-0000-0000-00000000c001',
   '{"reason_code":"RC2","verdict_evidence":{"fine_cents":30000}}'::jsonb),
  ('b2000000-0000-0000-0000-00000000e003',
   'b2000000-0000-0000-0000-000000000001',
   '2026-05-20 08:00:00+00'::timestamptz,
   'SANCTION_RECOMMENDED',
   'b2000000-0000-0000-0000-00000000c001',
   '{"reason_code":"RC3","verdict_evidence":{"fine_cents":15000,"rule_type":"MAX_TOLERANCE_DELAY"}}'::jsonb);

-- Record ledger count before simulation (for Red-Team test #16)
CREATE TEMP TABLE _pre_sim_ledger_count AS
  SELECT count(*)::int AS cnt FROM public.sla_audit_ledger_v2;

-- ── 1: Function exists ──────────────────────────────────────────────────────
SELECT has_function('public', 'simulate_sla_sandbox',
  ARRAY['uuid','uuid','timestamptz','timestamptz','jsonb','text'],
  '#1 simulate_sla_sandbox function exists');

-- ── 2-3: Claim mismatch (INV-26) ───────────────────────────────────────────
-- Set JWT as Org B, try to simulate Org A's contract
SELECT set_config('request.jwt.claims',
  '{"app_metadata": {"org_id": "b2000000-0000-0000-0000-000000000002", "role": "TENANT_ADMIN"}}',
  true);

SELECT throws_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c001',
    '2026-01-01'::timestamptz, '2026-07-01'::timestamptz,
    '{}'::jsonb, 'claim mismatch test')$$,
  'P0002', NULL,
  '#2 claim mismatch raises no_data_found (INV-26)');

SELECT set_config('request.jwt.claims', '', true);

-- ── 4: Contract not found (INV-26) ──────────────────────────────────────────
SELECT throws_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c999'::uuid,
    '2026-01-01'::timestamptz, '2026-07-01'::timestamptz,
    '{}'::jsonb, 'not found test')$$,
  'P0002', NULL,
  '#4 non-existent contract raises no_data_found (INV-26)');

-- ── 5: Period > 6 months ────────────────────────────────────────────────────
SELECT throws_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c001',
    '2025-01-01'::timestamptz, '2026-01-01'::timestamptz,
    '{}'::jsonb, '12 months')$$,
  '22023', NULL,
  '#5 period > 6 months raises invalid_parameter_value');

-- ── 6: Period end <= start ──────────────────────────────────────────────────
SELECT throws_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c001',
    '2026-06-01'::timestamptz, '2026-01-01'::timestamptz,
    '{}'::jsonb, 'reverse period')$$,
  '22023', NULL,
  '#6 period end <= start raises invalid_parameter_value');

-- ── 7-10: Full simulation with override ─────────────────────────────────────
-- Override: NO_SHOW_PENALTY multiplier 0.5 (halve the fine)
-- Baseline: 20000 + 30000 + 15000 = 65000
-- Simulated: 20000 + 15000 (half of 30000) + 15000 = 50000
-- Delta: 65000 - 50000 = 15000

SELECT lives_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c001',
    '2026-01-01'::timestamptz, '2026-07-01'::timestamptz,
    '{"overrides": [{"rule_type": "NO_SHOW_PENALTY", "rule_config": {"multiplier_value": 0.5}}]}'::jsonb,
    'half no-show test')$$,
  '#7 simulation executes successfully');

SELECT is(
  (SELECT baseline_total_fines_cents
     FROM public.sandbox_simulation_sessions
    WHERE session_label = 'half no-show test'
      AND organization_id = 'b2000000-0000-0000-0000-000000000001'),
  65000::bigint,
  '#8 baseline total = 65000 cents (20k + 30k + 15k)');

SELECT is(
  (SELECT simulated_total_fines_cents
     FROM public.sandbox_simulation_sessions
    WHERE session_label = 'half no-show test'
      AND organization_id = 'b2000000-0000-0000-0000-000000000001'),
  50000::bigint,
  '#9 simulated total = 50000 cents (20k + 15k + 15k)');

SELECT is(
  (SELECT delta_cents
     FROM public.sandbox_simulation_sessions
    WHERE session_label = 'half no-show test'
      AND organization_id = 'b2000000-0000-0000-0000-000000000001'),
  15000::bigint,
  '#10 delta = 15000 cents savings');

-- ── 11-12: Override not matching: was_override_applied = false ──────────────
SELECT is(
  (SELECT count(*)::int FROM public.sandbox_simulation_results r
    JOIN public.sandbox_simulation_sessions s ON s.id = r.session_id
   WHERE s.session_label = 'half no-show test'
     AND r.was_override_applied = false
     AND r.source_event_type = 'SANCTION_RECOMMENDED'),
  2,
  '#11 SANCTION_RECOMMENDED events NOT overridden (no matching override)');

SELECT is(
  (SELECT count(*)::int FROM public.sandbox_simulation_results r
    JOIN public.sandbox_simulation_sessions s ON s.id = r.session_id
   WHERE s.session_label = 'half no-show test'
     AND r.was_override_applied = true
     AND r.source_event_type = 'NO_SHOW_PENALTY'),
  1,
  '#12 NO_SHOW_PENALTY event was overridden');

-- ── 13-14: Financial override: simulated cap ────────────────────────────────
-- Use a cap of 40000 cents. Events: 20000 + 30000 + 15000.
-- Month boundaries: Mar=20000 (ok), Apr=30000 (ok), May=15000 (ok) — different months.
-- With all in same month hypothetical: need same-month events for cap test.
-- Instead, test by overriding cap to a very low value:
-- cap 25000. Mar: 20000 (ok, accrued=20000). Apr: 30000>remaining=? reset to 0, so 30000 ok.
-- Months are independent, so cap applies per-month. All 3 events are in different months.
-- Use financial_overrides.monthly_penalty_cap_cents = 25000.
-- Mar: 20000 < 25000 → ok. Apr: 30000 > 25000 → truncated to 25000. May: 15000 < 25000 → ok.
-- Simulated total = 20000 + 25000 + 15000 = 60000

SELECT lives_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c001',
    '2026-01-01'::timestamptz, '2026-07-01'::timestamptz,
    '{"financial_overrides": {"monthly_penalty_cap_cents": 25000}}'::jsonb,
    'cap test')$$,
  '#13 simulation with cap override executes');

SELECT is(
  (SELECT simulated_total_fines_cents
     FROM public.sandbox_simulation_sessions
    WHERE session_label = 'cap test'
      AND organization_id = 'b2000000-0000-0000-0000-000000000001'),
  60000::bigint,
  '#14 simulated total with cap = 60000 (20k + 25k-capped + 15k)');

-- ── 15: Session quota ───────────────────────────────────────────────────────
-- We already have 2 sessions. Insert 48 more to reach 50, then test rejection.
-- (Using direct INSERT to avoid running 48 simulations)
INSERT INTO public.sandbox_simulation_sessions
  (organization_id, contract_id, session_label,
   period_start_utc, period_end_utc, overrides_snapshot,
   baseline_total_fines_cents, simulated_total_fines_cents, delta_cents,
   baseline_event_count, created_by_user_id, expires_at_utc)
SELECT
  'b2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-00000000c001',
  'quota filler ' || i,
  '2026-01-01'::timestamptz, '2026-02-01'::timestamptz, '{}'::jsonb,
  0, 0, 0, 0,
  'b2000000-0000-0000-0000-000000000001',
  NOW() + INTERVAL '30 days'
FROM generate_series(1, 48) AS i;

SELECT throws_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c001',
    '2026-01-01'::timestamptz, '2026-02-01'::timestamptz,
    '{}'::jsonb, 'quota exceeded')$$,
  '54000', NULL,
  '#15 session quota (50) exceeded raises program_limit_exceeded');

-- Clean up quota sessions so following tests for this org don't fail (bypass INV-3 for test)
SELECT set_config('app.gc_sandbox', 'true', true);
DELETE FROM public.sandbox_simulation_sessions WHERE session_label LIKE 'quota filler %';
SELECT set_config('app.gc_sandbox', '', true);

-- ── 16: Red-Team: simulation does NOT write to sla_audit_ledger_v2 ──────────
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2),
  (SELECT cnt FROM _pre_sim_ledger_count),
  '#16 RED-TEAM: sla_audit_ledger_v2 row count unchanged after simulation');

-- ── 17: Empty period = session with zero totals ─────────────────────────────
-- Use uncapped contract with no events in period
SELECT lives_ok(
  $$SELECT simulate_sla_sandbox(
    'b2000000-0000-0000-0000-000000000001'::uuid,
    'b2000000-0000-0000-0000-00000000c002',
    '2025-01-01'::timestamptz, '2025-02-01'::timestamptz,
    '{}'::jsonb, 'empty period')$$,
  '#17 simulation with no events executes (zero totals)');

-- ── 18: delta_bps computation ───────────────────────────────────────────────
SELECT is(
  (SELECT delta_bps
     FROM public.sandbox_simulation_sessions
    WHERE session_label = 'half no-show test'
      AND organization_id = 'b2000000-0000-0000-0000-000000000001'),
  2307,  -- (15000 * 10000) / 65000 = 2307 bps (23.07% savings)
  '#18 delta_bps computed correctly');

SELECT * FROM finish();
ROLLBACK;
