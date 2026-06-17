BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(4);

-- =============================================================================
-- pgTAP: fix_location_label_rpc test
-- Migration: 20260820000002_fix_location_label_rpc.sql
-- Focus: Verify that read_infraction_context correctly extracts location_label
-- from verdict_evidence prioritizing geofence_name over address over location_label.
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains, logo_url
) VALUES (
  'b3b3b3b3-0000-0000-0000-000000000010', 'Org Location Test', 'Org Location Test SA',
  'b3b30000000010', 'America/Sao_Paulo', 'BRL', 'enterprise', 50, 5, 3000,
  300, 15, 'loc@test.com', 'EXT_LOC', 'LOGISTICS', ARRAY['loc.com'],
  'https://cdn.example.com/logos/loc.png'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id,
   verdict_evidence, status, vehicle_plate)
VALUES 
  -- T1: Prioritize geofence_name
  (
    'b3b3b3b3-0000-0000-0000-000000000020',
    'b3b3b3b3-0000-0000-0000-000000000010',
    'b3b3b3b3-0000-0000-0000-000000000f20',
    'set-loc',
    'b3b3b3b3-0000-0000-0000-000000000030',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-20T10:00:00Z',
      'geofence_name', 'CD Guarulhos',
      'address', 'Rua Secundária',
      'location_label', 'Label Ignorado',
      'primary_evidence_lat', '-23.5',
      'primary_evidence_lng', '-46.5'
    ),
    'pending',
    'LOC-001'
  ),
  -- T2: Fallback to address
  (
    'b3b3b3b3-0000-0000-0000-000000000021',
    'b3b3b3b3-0000-0000-0000-000000000010',
    'b3b3b3b3-0000-0000-0000-000000000f21',
    'set-loc',
    'b3b3b3b3-0000-0000-0000-000000000030',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-20T10:00:00Z',
      'address', 'Rua Principal',
      'location_label', 'Label Ignorado',
      'primary_evidence_lat', '-23.5',
      'primary_evidence_lng', '-46.5'
    ),
    'pending',
    'LOC-002'
  ),
  -- T3: Fallback to location_label
  (
    'b3b3b3b3-0000-0000-0000-000000000022',
    'b3b3b3b3-0000-0000-0000-000000000010',
    'b3b3b3b3-0000-0000-0000-000000000f22',
    'set-loc',
    'b3b3b3b3-0000-0000-0000-000000000030',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-20T10:00:00Z',
      'location_label', 'Label Correto',
      'primary_evidence_lat', '-23.5',
      'primary_evidence_lng', '-46.5'
    ),
    'pending',
    'LOC-003'
  ),
  -- T4: Fallback to lat,lng
  (
    'b3b3b3b3-0000-0000-0000-000000000023',
    'b3b3b3b3-0000-0000-0000-000000000010',
    'b3b3b3b3-0000-0000-0000-000000000f23',
    'set-loc',
    'b3b3b3b3-0000-0000-0000-000000000030',
    jsonb_build_object(
      'fine_cents', 50000,
      'primary_evidence_timestamp_utc', '2026-08-20T10:00:00Z',
      'primary_evidence_lat', '-23.5',
      'primary_evidence_lng', '-46.5'
    ),
    'pending',
    'LOC-004'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_portal_tokens
  (token, organization_id, queue_entry_id, created_by_user_id,
   expires_at_utc, max_access_count, created_at_utc)
VALUES
  ('b3b30010-0000-0000-0000-000000000000', 'b3b3b3b3-0000-0000-0000-000000000010', 'b3b3b3b3-0000-0000-0000-000000000020', 'b3b3b3b3-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5, NOW()),
  ('b3b30011-0000-0000-0000-000000000000', 'b3b3b3b3-0000-0000-0000-000000000010', 'b3b3b3b3-0000-0000-0000-000000000021', 'b3b3b3b3-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5, NOW()),
  ('b3b30012-0000-0000-0000-000000000000', 'b3b3b3b3-0000-0000-0000-000000000010', 'b3b3b3b3-0000-0000-0000-000000000022', 'b3b3b3b3-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5, NOW()),
  ('b3b30013-0000-0000-0000-000000000000', 'b3b3b3b3-0000-0000-0000-000000000010', 'b3b3b3b3-0000-0000-0000-000000000023', 'b3b3b3b3-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5, NOW())
ON CONFLICT (token) DO NOTHING;

-- T1: Extract geofence_name
SELECT is(
  (SELECT public.read_infraction_context('b3b30010-0000-0000-0000-000000000000') ->> 'location_label'),
  'CD Guarulhos',
  'T1: Prioritizes geofence_name'
);

-- T2: Extract address
SELECT is(
  (SELECT public.read_infraction_context('b3b30011-0000-0000-0000-000000000000') ->> 'location_label'),
  'Rua Principal',
  'T2: Falls back to address'
);

-- T3: Extract location_label
SELECT is(
  (SELECT public.read_infraction_context('b3b30012-0000-0000-0000-000000000000') ->> 'location_label'),
  'Label Correto',
  'T3: Falls back to location_label'
);

-- T4: Extract lat,lng
SELECT is(
  (SELECT public.read_infraction_context('b3b30013-0000-0000-0000-000000000000') ->> 'location_label'),
  '-23.5,-46.5',
  'T4: Falls back to lat,lng'
);

SELECT * FROM finish();
ROLLBACK;
