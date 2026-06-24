-- pr_scanner: ignore-regression (companion test for 20260822000002)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(4);

-- =============================================================================
-- pgTAP: fix_location_label_regression companion test
-- Migration: 20260822000002_fix_location_label_regression.sql
-- Focus: Verify COALESCE priority geofence_name → address → location_label →
--        lat,lng is correctly restored in read_infraction_context.
-- INV-1, INV-22, INV-26.
-- =============================================================================

INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('dd000000-0000-0000-0000-000000000010'::uuid, 'DD Loc Regression Org', '33333333333301')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES
  -- T1: geofence_name should win over all other fields
  (
    'dd000000-0000-0000-0000-000000000020'::uuid,
    'dd000000-0000-0000-0000-000000000010'::uuid,
    'dd000000-0000-0000-0000-000000000f20'::uuid,
    'set-dd', 'dd-contract',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z',
      'geofence_name', 'CD Campinas',
      'address', 'Rua Secundaria DD',
      'location_label', 'Label DD Ignorado',
      'primary_evidence_lat', '-22.9',
      'primary_evidence_lng', '-47.1'
    ),
    'pending', 'DD-001'
  ),
  -- T2: no geofence_name → address wins
  (
    'dd000000-0000-0000-0000-000000000021'::uuid,
    'dd000000-0000-0000-0000-000000000010'::uuid,
    'dd000000-0000-0000-0000-000000000f21'::uuid,
    'set-dd', 'dd-contract',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z',
      'address', 'Avenida DD Principal',
      'location_label', 'Label DD Ignorado',
      'primary_evidence_lat', '-22.9',
      'primary_evidence_lng', '-47.1'
    ),
    'pending', 'DD-002'
  ),
  -- T3: no geofence_name, no address → location_label wins
  (
    'dd000000-0000-0000-0000-000000000022'::uuid,
    'dd000000-0000-0000-0000-000000000010'::uuid,
    'dd000000-0000-0000-0000-000000000f22'::uuid,
    'set-dd', 'dd-contract',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z',
      'location_label', 'Label DD Correto',
      'primary_evidence_lat', '-22.9',
      'primary_evidence_lng', '-47.1'
    ),
    'pending', 'DD-003'
  ),
  -- T4: no text label fields → lat,lng fallback
  (
    'dd000000-0000-0000-0000-000000000023'::uuid,
    'dd000000-0000-0000-0000-000000000010'::uuid,
    'dd000000-0000-0000-0000-000000000f23'::uuid,
    'set-dd', 'dd-contract',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-22T10:00:00Z',
      'primary_evidence_lat', '-22.9',
      'primary_evidence_lng', '-47.1'
    ),
    'pending', 'DD-004'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES
  ('dd000010-0000-0000-0000-000000000000'::uuid, 'dd000000-0000-0000-0000-000000000010'::uuid, 'dd000000-0000-0000-0000-000000000020'::uuid, 'dd000000-0000-0000-0000-0000000000b1'::uuid, NOW() + INTERVAL '24 hours', 5, NOW()),
  ('dd000011-0000-0000-0000-000000000000'::uuid, 'dd000000-0000-0000-0000-000000000010'::uuid, 'dd000000-0000-0000-0000-000000000021'::uuid, 'dd000000-0000-0000-0000-0000000000b1'::uuid, NOW() + INTERVAL '24 hours', 5, NOW()),
  ('dd000012-0000-0000-0000-000000000000'::uuid, 'dd000000-0000-0000-0000-000000000010'::uuid, 'dd000000-0000-0000-0000-000000000022'::uuid, 'dd000000-0000-0000-0000-0000000000b1'::uuid, NOW() + INTERVAL '24 hours', 5, NOW()),
  ('dd000013-0000-0000-0000-000000000000'::uuid, 'dd000000-0000-0000-0000-000000000010'::uuid, 'dd000000-0000-0000-0000-000000000023'::uuid, 'dd000000-0000-0000-0000-0000000000b1'::uuid, NOW() + INTERVAL '24 hours', 5, NOW())
ON CONFLICT (token) DO NOTHING;

-- T1: geofence_name takes priority
SELECT is(
  (SELECT public.read_infraction_context('dd000010-0000-0000-0000-000000000000'::uuid) ->> 'location_label'),
  'CD Campinas',
  'T1: geofence_name wins over address and location_label (COALESCE restored)'
);

-- T2: address wins when no geofence_name
SELECT is(
  (SELECT public.read_infraction_context('dd000011-0000-0000-0000-000000000000'::uuid) ->> 'location_label'),
  'Avenida DD Principal',
  'T2: address wins when geofence_name absent'
);

-- T3: location_label wins when no geofence_name or address
SELECT is(
  (SELECT public.read_infraction_context('dd000012-0000-0000-0000-000000000000'::uuid) ->> 'location_label'),
  'Label DD Correto',
  'T3: location_label wins when geofence_name and address absent'
);

-- T4: lat,lng fallback when no text label fields present
SELECT is(
  (SELECT public.read_infraction_context('dd000013-0000-0000-0000-000000000000'::uuid) ->> 'location_label'),
  '-22.9,-47.1',
  'T4: falls back to lat,lng when no text label fields present'
);

SELECT * FROM finish();
ROLLBACK;
