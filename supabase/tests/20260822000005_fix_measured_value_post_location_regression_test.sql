BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- =============================================================================
-- pgTAP: read_infraction_context — location_label COALESCE + math regression
-- Migration: 20260822000005_fix_measured_value_post_location_regression.sql
-- Focus:
--   1. location_label COALESCE priority: geofence_name → address →
--      location_label → lat,lng → '-'
--   2. Math regression guard: measured = threshold + delta; exceeded = delta.
--      Verifies 20260822000002 did not survive as the live definer.
-- Seeds use d5d5 prefix namespace to avoid collision with prior test files.
-- =============================================================================

-- ── Org seed ─────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains, logo_url
) VALUES (
  'd5d5d5d5-0000-0000-0000-000000000001', 'Org Loc Fix', 'Org Loc Fix SA',
  'd5d50000000001', 'America/Sao_Paulo', 'BRL', 'enterprise', 50, 5, 3000,
  300, 15, 'locfix@test.com', 'EXT_LOCFIX', 'LOGISTICS', ARRAY['locfix.com'],
  'https://cdn.example.com/logos/locfix.png'
) ON CONFLICT (id) DO NOTHING;

-- ── Queue entries ─────────────────────────────────────────────────────────────
-- A: geofence_name present — must win over address and lat/lng.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'd5d5d5d5-0000-0000-0000-000000000011',
  'd5d5d5d5-0000-0000-0000-000000000001',
  'd5d5d5d5-0000-0000-0000-0000000000a1',
  'set-loc-a', 'd5d5d5d5-0000-0000-0000-0000000000a2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    5.0,
    'threshold_value',                60.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333',
    'geofence_name',                  'Terminal Tietê',
    'address',                        'Av. Cruzeiro do Sul, 1800'
  ),
  'pending', 'LOC-TESTA'
) ON CONFLICT (id) DO NOTHING;

-- B: no geofence_name; address present — must win over lat/lng.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'd5d5d5d5-0000-0000-0000-000000000012',
  'd5d5d5d5-0000-0000-0000-000000000001',
  'd5d5d5d5-0000-0000-0000-0000000000b1',
  'set-loc-b', 'd5d5d5d5-0000-0000-0000-0000000000b2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    5.0,
    'threshold_value',                60.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-22T10:01:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333',
    'address',                        'Rua da Consolação, 500'
  ),
  'pending', 'LOC-TESTB'
) ON CONFLICT (id) DO NOTHING;

-- C: only location_label field — no lat/lng, no geofence_name, no address.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'd5d5d5d5-0000-0000-0000-000000000013',
  'd5d5d5d5-0000-0000-0000-000000000001',
  'd5d5d5d5-0000-0000-0000-0000000000c1',
  'set-loc-c', 'd5d5d5d5-0000-0000-0000-0000000000c2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    5.0,
    'threshold_value',                60.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-22T10:02:00Z',
    'location_label',                 'Pátio Central Norte'
  ),
  'pending', 'LOC-TESTC'
) ON CONFLICT (id) DO NOTHING;

-- D: only lat/lng — no named location fields.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'd5d5d5d5-0000-0000-0000-000000000014',
  'd5d5d5d5-0000-0000-0000-000000000001',
  'd5d5d5d5-0000-0000-0000-0000000000d1',
  'set-loc-d', 'd5d5d5d5-0000-0000-0000-0000000000d2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    5.0,
    'threshold_value',                60.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-22T10:03:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333'
  ),
  'pending', 'LOC-TESTD'
) ON CONFLICT (id) DO NOTHING;

-- E: no location fields at all — must return '-'.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'd5d5d5d5-0000-0000-0000-000000000015',
  'd5d5d5d5-0000-0000-0000-000000000001',
  'd5d5d5d5-0000-0000-0000-0000000000e1',
  'set-loc-e', 'd5d5d5d5-0000-0000-0000-0000000000e2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    5.0,
    'threshold_value',                60.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-22T10:04:00Z'
  ),
  'pending', 'LOC-TESTE'
) ON CONFLICT (id) DO NOTHING;

-- F: math regression check — delta=12.0, threshold=40.0 → measured=52, exceeded=12.
--    If 20260822000002 were the live definer: measured=12, exceeded=12-40=-28.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES (
  'd5d5d5d5-0000-0000-0000-000000000016',
  'd5d5d5d5-0000-0000-0000-000000000001',
  'd5d5d5d5-0000-0000-0000-0000000000f1',
  'set-loc-f', 'd5d5d5d5-0000-0000-0000-0000000000f2',
  jsonb_build_object(
    'fine_cents',                     10000,
    'delta_value',                    12.0,
    'threshold_value',                40.0,
    'clause_ref',                     'VEL-01',
    'primary_evidence_timestamp_utc', '2026-08-22T10:05:00Z',
    'primary_evidence_lat',           '-23.5505',
    'primary_evidence_lng',           '-46.6333'
  ),
  'pending', 'LOC-TESTF'
) ON CONFLICT (id) DO NOTHING;

-- ── Tokens ────────────────────────────────────────────────────────────────────
INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES
  ('d5d50011-0000-0000-0000-000000000000',
   'd5d5d5d5-0000-0000-0000-000000000001',
   'd5d5d5d5-0000-0000-0000-000000000011',
   'd5d5d5d5-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('d5d50012-0000-0000-0000-000000000000',
   'd5d5d5d5-0000-0000-0000-000000000001',
   'd5d5d5d5-0000-0000-0000-000000000012',
   'd5d5d5d5-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('d5d50013-0000-0000-0000-000000000000',
   'd5d5d5d5-0000-0000-0000-000000000001',
   'd5d5d5d5-0000-0000-0000-000000000013',
   'd5d5d5d5-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('d5d50014-0000-0000-0000-000000000000',
   'd5d5d5d5-0000-0000-0000-000000000001',
   'd5d5d5d5-0000-0000-0000-000000000014',
   'd5d5d5d5-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('d5d50015-0000-0000-0000-000000000000',
   'd5d5d5d5-0000-0000-0000-000000000001',
   'd5d5d5d5-0000-0000-0000-000000000015',
   'd5d5d5d5-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW()),
  ('d5d50016-0000-0000-0000-000000000000',
   'd5d5d5d5-0000-0000-0000-000000000001',
   'd5d5d5d5-0000-0000-0000-000000000016',
   'd5d5d5d5-0000-0000-0000-0000000000ff',
   NOW() + INTERVAL '24 hours', 5, NOW())
ON CONFLICT (token) DO NOTHING;

-- =============================================================================
-- T1: geofence_name wins over address and lat,lng.
-- =============================================================================
SELECT is(
  (SELECT public.read_infraction_context('d5d50011-0000-0000-0000-000000000000')
         ->> 'location_label'),
  'Terminal Tietê',
  'T1: geofence_name present → location_label = geofence_name (highest priority)'
);

-- =============================================================================
-- T2: address wins when geofence_name absent.
-- =============================================================================
SELECT is(
  (SELECT public.read_infraction_context('d5d50012-0000-0000-0000-000000000000')
         ->> 'location_label'),
  'Rua da Consolação, 500',
  'T2: no geofence_name → location_label = address'
);

-- =============================================================================
-- T3: location_label field used when only that is present.
-- =============================================================================
SELECT is(
  (SELECT public.read_infraction_context('d5d50013-0000-0000-0000-000000000000')
         ->> 'location_label'),
  'Pátio Central Norte',
  'T3: only location_label field → location_label = that field'
);

-- =============================================================================
-- T4: lat,lng concatenation when no named location fields present.
-- =============================================================================
SELECT is(
  (SELECT public.read_infraction_context('d5d50014-0000-0000-0000-000000000000')
         ->> 'location_label'),
  '-23.5505,-46.6333',
  'T4: only lat/lng → location_label = "lat,lng" concatenation'
);

-- =============================================================================
-- T5: fallback '-' when all location fields absent.
-- =============================================================================
SELECT is(
  (SELECT public.read_infraction_context('d5d50015-0000-0000-0000-000000000000')
         ->> 'location_label'),
  '-',
  'T5: no location fields → location_label = ''-'''
);

-- =============================================================================
-- T6: Math regression — measured = threshold + delta, not just delta.
--     If 20260822000002 were live: measured = ROUND(12) = 12, not 52.
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('d5d50016-0000-0000-0000-000000000000')
          ->> 'measured_value')::int),
  52,
  'T6 (math regression): measured_value = ROUND(40 + 12) = 52, not ROUND(12) = 12'
);

-- =============================================================================
-- T7: Math regression — exceeded = ROUND(delta), not measured - threshold.
--     If 20260822000002 were live: exceeded = 12 - 40 = -28.
-- =============================================================================
SELECT is(
  (SELECT (public.read_infraction_context('d5d50016-0000-0000-0000-000000000000')
          ->> 'exceeded_by')::int),
  12,
  'T7 (math regression): exceeded_by = ROUND(delta) = 12, not measured - threshold = -28'
);

SELECT * FROM finish();
ROLLBACK;
