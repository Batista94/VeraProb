BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- =============================================================================
-- pgTAP: read_infraction_context — measured_value / exceeded_by math contract
-- Migration: 20260821000004_fix_infraction_context_measured_value.sql
--            (consolidated into 20260822000005 as authoritative definer)
-- Focus: delta_value is the EXCESS; measured = threshold + delta; exceeded = delta.
--        Tests use a dedicated org/token namespace (c4c4 prefix) to avoid
--        collision with 20260819000003 test seeds.
-- =============================================================================

-- ── Org seed ─────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains, logo_url
) VALUES (
  'c4c4c4c4-0000-0000-0000-000000000001', 'Org MV Fix', 'Org MV Fix SA',
  'c4c40000000001', 'America/Sao_Paulo', 'BRL', 'enterprise', 50, 5, 3000,
  300, 15, 'mvfix@test.com', 'EXT_MVFIX', 'LOGISTICS', ARRAY['mvfix.com'],
  'https://cdn.example.com/logos/mvfix.png'
) ON CONFLICT (id) DO NOTHING;

-- ── Queue entries — four evidence configurations ──────────────────────────────
-- A: integer delta=10, threshold=80 → measured=90, exceeded=10
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'c4c4c4c4-0000-0000-0000-000000000011',
  'c4c4c4c4-0000-0000-0000-000000000001',
  'c4c4c4c4-0000-0000-0000-0000000000a1',
  'set-mv-a', 'c4c4c4c4-0000-0000-0000-0000000000a2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    10.0,
    'threshold_value',                80.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-21T10:00:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333'
  ),
  'pending', 'MV-TESTA'
) ON CONFLICT (id) DO NOTHING;

-- B: real-world bug case — delta=8.5, threshold=80 → measured=89, exceeded=9
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'c4c4c4c4-0000-0000-0000-000000000012',
  'c4c4c4c4-0000-0000-0000-000000000001',
  'c4c4c4c4-0000-0000-0000-0000000000b1',
  'set-mv-b', 'c4c4c4c4-0000-0000-0000-0000000000b2',
  jsonb_build_object(
    'fine_cents',                     20000,
    'delta_value',                    8.5,
    'threshold_value',                80.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-21T10:01:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333'
  ),
  'pending', 'MV-TESTB'
) ON CONFLICT (id) DO NOTHING;

-- C: missing delta_value → measured and exceeded must be NULL
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'c4c4c4c4-0000-0000-0000-000000000013',
  'c4c4c4c4-0000-0000-0000-000000000001',
  'c4c4c4c4-0000-0000-0000-0000000000c1',
  'set-mv-c', 'c4c4c4c4-0000-0000-0000-0000000000c2',
  jsonb_build_object(
    'fine_cents',                     5000,
    'threshold_value',                60.0,
    'clause_ref',                     'VEL-02',
    'primary_evidence_timestamp_utc', '2026-08-21T10:02:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333'
  ),
  'pending', 'MV-TESTC'
) ON CONFLICT (id) DO NOTHING;

-- D: rounding — delta=7.5, threshold=5.0 → measured=ROUND(12.5)=13, exceeded=ROUND(7.5)=8
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'c4c4c4c4-0000-0000-0000-000000000014',
  'c4c4c4c4-0000-0000-0000-000000000001',
  'c4c4c4c4-0000-0000-0000-0000000000d1',
  'set-mv-d', 'c4c4c4c4-0000-0000-0000-0000000000d2',
  jsonb_build_object(
    'fine_cents',                     3000,
    'delta_value',                    7.5,
    'threshold_value',                5.0,
    'clause_ref',                     'ATR-01',
    'primary_evidence_timestamp_utc', '2026-08-21T10:03:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333'
  ),
  'pending', 'MV-TESTD'
) ON CONFLICT (id) DO NOTHING;

-- ── Tokens (valid, non-expiring) ──────────────────────────────────────────────
INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES
  ('c4c40011-0000-0000-0000-000000000000',
   'c4c4c4c4-0000-0000-0000-000000000001',
   'c4c4c4c4-0000-0000-0000-000000000011',
   'c4c4c4c4-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('c4c40012-0000-0000-0000-000000000000',
   'c4c4c4c4-0000-0000-0000-000000000001',
   'c4c4c4c4-0000-0000-0000-000000000012',
   'c4c4c4c4-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('c4c40013-0000-0000-0000-000000000000',
   'c4c4c4c4-0000-0000-0000-000000000001',
   'c4c4c4c4-0000-0000-0000-000000000013',
   'c4c4c4c4-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('c4c40014-0000-0000-0000-000000000000',
   'c4c4c4c4-0000-0000-0000-000000000001',
   'c4c4c4c4-0000-0000-0000-000000000014',
   'c4c4c4c4-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW())
ON CONFLICT (token) DO NOTHING;

-- =============================================================================
-- T1: Integer delta + threshold — measured = threshold + delta (not just delta).
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('c4c40011-0000-0000-0000-000000000000')
          ->> 'measured_value')::int),
  90,
  'T1: measured_value = ROUND(80 + 10) = 90, not ROUND(10)'
);

-- =============================================================================
-- T2: exceeded_by = delta directly (not measured - threshold).
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('c4c40011-0000-0000-0000-000000000000')
          ->> 'exceeded_by')::int),
  10,
  'T2: exceeded_by = ROUND(delta_value) = 10, not v_measured - v_threshold'
);

-- =============================================================================
-- T3: Real-world bug case — portal showed Medido=9, Excesso=-71 for this input.
--     Correct: ROUND(80 + 8.5) = ROUND(88.5) = 89.
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('c4c40012-0000-0000-0000-000000000000')
          ->> 'measured_value')::int),
  89,
  'T3 (bug regression): delta=8.5 threshold=80 → measured_value=89, not 9'
);

-- =============================================================================
-- T4: Real-world bug case — exceeded must be ROUND(delta) = ROUND(8.5) = 9.
--     Old formula produced 9 - 80 = -71.
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('c4c40012-0000-0000-0000-000000000000')
          ->> 'exceeded_by')::int),
  9,
  'T4 (bug regression): delta=8.5 threshold=80 → exceeded_by=9, not -71'
);

-- =============================================================================
-- T5: NULL guard — no delta_value in JSONB → measured_value IS NULL.
-- =============================================================================
SELECT ok(
  (SELECT (public.read_infraction_context('c4c40013-0000-0000-0000-000000000000')
          ->> 'measured_value') IS NULL),
  'T5: missing delta_value → measured_value = NULL'
);

-- =============================================================================
-- T6: NULL guard — no delta_value → exceeded_by IS NULL.
-- =============================================================================
SELECT ok(
  (SELECT (public.read_infraction_context('c4c40013-0000-0000-0000-000000000000')
          ->> 'exceeded_by') IS NULL),
  'T6: missing delta_value → exceeded_by = NULL'
);

-- =============================================================================
-- T7: Rounding — ROUND(5.0 + 7.5) = ROUND(12.5) = 13 for numeric type.
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('c4c40014-0000-0000-0000-000000000000')
          ->> 'measured_value')::int),
  13,
  'T7: measured_value = ROUND(5.0 + 7.5) = 13'
);

-- =============================================================================
-- T8: Rounding — ROUND(7.5) = 8 for numeric type.
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('c4c40014-0000-0000-0000-000000000000')
          ->> 'exceeded_by')::int),
  8,
  'T8: exceeded_by = ROUND(7.5) = 8'
);

SELECT * FROM finish();
ROLLBACK;
