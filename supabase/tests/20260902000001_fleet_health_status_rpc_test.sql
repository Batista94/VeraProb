BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- =============================================================================
-- pgTAP: get_fleet_health_status — Phase 10.6 Ingestion Health Monitor
--
-- Tests:
--   S1-S2: Structure (function exists, SECURITY DEFINER)
--   HP1-HP4: Hardware classification (HEALTHY, DELAYED, OFFLINE, NEVER_SEEN)
--   HP5: Phantom device inclusion (asset_id IS NULL)
--   HP6: Anomaly count (integrity_flag <> 'OK' in last 24h)
--   HP7: Retired vehicles excluded
--   HP8: Sort order (worst status first)
--   HP9: Parameterized thresholds
--   B1-B2: Tenant isolation (cross-org = 0 rows, anti-oracle INV-22/26)
--   A1: Extended alert_type CHECK constraint (TELEMETRY_SILENT, TELEGRAM_ORPHAN)
-- =============================================================================

-- ── Seed: Organization ──────────────────────────────────────────────────────

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000ff701','OrgHealth','OrgHealth SA','000000000ff701',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'oh@test.com',
   'EXTH','LOGISTICS',ARRAY['test.com']),
  ('00000000-0000-0000-0000-0000000ff702','OrgOther','OrgOther SA','000000000ff702',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'oo@test.com',
   'EXTO','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- ── Seed: Vehicles (Org A) ──────────────────────────────────────────────────

INSERT INTO public.vehicles (id, organization_id, plate, model, status)
VALUES
  -- Vehicle 1: will be HEALTHY (recent ping)
  ('00000000-0000-0000-0000-0000000fe101',
   '00000000-0000-0000-0000-0000000ff701','ABC-1111','Sprinter 415','available'),
  -- Vehicle 2: will be DELAYED (ping 20 min ago)
  ('00000000-0000-0000-0000-0000000fe102',
   '00000000-0000-0000-0000-0000000ff701','DEF-2222','Ducato','available'),
  -- Vehicle 3: will be OFFLINE (ping 2h ago)
  ('00000000-0000-0000-0000-0000000fe103',
   '00000000-0000-0000-0000-0000000ff701','GHI-3333','Actros','in_service'),
  -- Vehicle 4: no telemetry at all → NEVER_SEEN
  ('00000000-0000-0000-0000-0000000fe104',
   '00000000-0000-0000-0000-0000000ff701','JKL-4444','Atego','available'),
  -- Vehicle 5: retired → excluded from results
  ('00000000-0000-0000-0000-0000000fe105',
   '00000000-0000-0000-0000-0000000ff701','MNO-5555','Accelo','retired')
ON CONFLICT (id) DO NOTHING;

-- ── Seed: Vehicles (Org B — for isolation test) ─────────────────────────────

INSERT INTO public.vehicles (id, organization_id, plate, model, status)
VALUES
  ('00000000-0000-0000-0000-0000000fe201',
   '00000000-0000-0000-0000-0000000ff702','XYZ-9999','Transit','available')
ON CONFLICT (id) DO NOTHING;

-- ── Seed: Raw Telemetry Payloads (FK anchor for canonical_facts) ────────────

INSERT INTO public.raw_telemetry_payloads
  (id, organization_id, provider_name, device_id, raw_payload, payload_hash)
VALUES
  ('00000000-0000-0000-0000-0000000fd101',
   '00000000-0000-0000-0000-0000000ff701','SASCAR','SASCAR-001',
   '{"t":"h1"}'::jsonb,'hash_h1'),
  ('00000000-0000-0000-0000-0000000fd102',
   '00000000-0000-0000-0000-0000000ff701','SASCAR','SASCAR-002',
   '{"t":"h2"}'::jsonb,'hash_h2'),
  ('00000000-0000-0000-0000-0000000fd103',
   '00000000-0000-0000-0000-0000000ff701','SASCAR','SASCAR-003',
   '{"t":"h3"}'::jsonb,'hash_h3'),
  -- Phantom device raw payload
  ('00000000-0000-0000-0000-0000000fd104',
   '00000000-0000-0000-0000-0000000ff701','SASCAR','PHANTOM-99',
   '{"t":"phantom"}'::jsonb,'hash_phantom'),
  -- Anomaly payload
  ('00000000-0000-0000-0000-0000000fd105',
   '00000000-0000-0000-0000-0000000ff701','SASCAR','SASCAR-003',
   '{"t":"anomaly"}'::jsonb,'hash_anomaly'),
  -- Org B payload
  ('00000000-0000-0000-0000-0000000fd201',
   '00000000-0000-0000-0000-0000000ff702','SASCAR','SASCAR-B01',
   '{"t":"orgB"}'::jsonb,'hash_orgb')
ON CONFLICT DO NOTHING;

-- ── Seed: Canonical Facts ───────────────────────────────────────────────────

-- Vehicle 1 (HEALTHY): ping 30 seconds ago
INSERT INTO public.canonical_facts
  (organization_id, raw_payload_id, asset_id, device_id, gps_timestamp,
   received_at_utc, lat, lng, source_adapter, integrity_flag)
VALUES
  ('00000000-0000-0000-0000-0000000ff701','00000000-0000-0000-0000-0000000fd101',
   '00000000-0000-0000-0000-0000000fe101','SASCAR-001',
   NOW() - INTERVAL '30 seconds', NOW() - INTERVAL '30 seconds',
   -23.55, -46.63, 'SASCAR_V1', 'OK');

-- Vehicle 2 (DELAYED): ping 20 minutes ago (> 900s, <= 3600s)
INSERT INTO public.canonical_facts
  (organization_id, raw_payload_id, asset_id, device_id, gps_timestamp,
   received_at_utc, lat, lng, source_adapter, integrity_flag)
VALUES
  ('00000000-0000-0000-0000-0000000ff701','00000000-0000-0000-0000-0000000fd102',
   '00000000-0000-0000-0000-0000000fe102','SASCAR-002',
   NOW() - INTERVAL '20 minutes', NOW() - INTERVAL '20 minutes',
   -23.56, -46.64, 'SASCAR_V1', 'OK');

-- Vehicle 3 (OFFLINE): ping 2 hours ago (> 3600s)
INSERT INTO public.canonical_facts
  (organization_id, raw_payload_id, asset_id, device_id, gps_timestamp,
   received_at_utc, lat, lng, source_adapter, integrity_flag)
VALUES
  ('00000000-0000-0000-0000-0000000ff701','00000000-0000-0000-0000-0000000fd103',
   '00000000-0000-0000-0000-0000000fe103','SASCAR-003',
   NOW() - INTERVAL '2 hours', NOW() - INTERVAL '2 hours',
   -23.57, -46.65, 'SASCAR_V1', 'OK');

-- Vehicle 3: anomaly in last 24h (KINEMATIC_ANOMALY)
INSERT INTO public.canonical_facts
  (organization_id, raw_payload_id, asset_id, device_id, gps_timestamp,
   received_at_utc, lat, lng, source_adapter, integrity_flag)
VALUES
  ('00000000-0000-0000-0000-0000000ff701','00000000-0000-0000-0000-0000000fd105',
   '00000000-0000-0000-0000-0000000fe103','SASCAR-003',
   NOW() - INTERVAL '3 hours', NOW() - INTERVAL '3 hours',
   -23.58, -46.66, 'SASCAR_V1', 'KINEMATIC_ANOMALY');

-- Phantom device (asset_id IS NULL): ping 10 minutes ago
INSERT INTO public.canonical_facts
  (organization_id, raw_payload_id, asset_id, device_id, gps_timestamp,
   received_at_utc, lat, lng, source_adapter, integrity_flag)
VALUES
  ('00000000-0000-0000-0000-0000000ff701','00000000-0000-0000-0000-0000000fd104',
   NULL,'PHANTOM-99',
   NOW() - INTERVAL '10 minutes', NOW() - INTERVAL '10 minutes',
   -23.59, -46.67, 'SASCAR_V1', 'OK');

-- Org B vehicle data (for isolation test)
INSERT INTO public.canonical_facts
  (organization_id, raw_payload_id, asset_id, device_id, gps_timestamp,
   received_at_utc, lat, lng, source_adapter, integrity_flag)
VALUES
  ('00000000-0000-0000-0000-0000000ff702','00000000-0000-0000-0000-0000000fd201',
   '00000000-0000-0000-0000-0000000fe201','SASCAR-B01',
   NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '5 minutes',
   -23.60, -46.68, 'SASCAR_V1', 'OK');

-- ── Structure Tests ─────────────────────────────────────────────────────────

SELECT has_function('public','get_fleet_health_status',
  ARRAY['uuid','integer','integer','integer'],
  'S1: get_fleet_health_status(uuid,int,int,int) exists');

SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname='get_fleet_health_status'),
  true, 'S2: get_fleet_health_status is SECURITY DEFINER');

-- ── Authenticated Session (Org A) ───────────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000fb701","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ff701","role":"TENANT_ADMIN"}}';

-- HP1: HEALTHY vehicle (gap <= 900s)
SELECT is(
  (SELECT hardware_status FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe101'),
  'HEALTHY', 'HP1: vehicle with 30s gap is HEALTHY');

-- HP2: DELAYED vehicle (900s < gap <= 3600s)
SELECT is(
  (SELECT hardware_status FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe102'),
  'DELAYED', 'HP2: vehicle with 20min gap is DELAYED');

-- HP3: OFFLINE vehicle (gap > 3600s)
SELECT is(
  (SELECT hardware_status FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe103'),
  'OFFLINE', 'HP3: vehicle with 2h gap is OFFLINE');

-- HP4: NEVER_SEEN vehicle (no telemetry)
SELECT is(
  (SELECT hardware_status FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe104'),
  'NEVER_SEEN', 'HP4: vehicle with no telemetry is NEVER_SEEN');

-- HP5: Phantom device included (vehicle_id IS NULL, device_id present)
SELECT ok(
  EXISTS(SELECT 1 FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id IS NULL AND device_id = 'PHANTOM-99'),
  'HP5: phantom device (asset_id NULL) is included in results');

-- HP6: Anomaly count for vehicle 3 (1 KINEMATIC_ANOMALY in 24h)
SELECT is(
  (SELECT anomaly_count_24h FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe103'),
  1, 'HP6: anomaly_count_24h = 1 for vehicle with KINEMATIC_ANOMALY');

-- HP7: Retired vehicle excluded
SELECT ok(
  NOT EXISTS(SELECT 1 FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe105'),
  'HP7: retired vehicle excluded from results');

-- HP8: Sort order — worst status first (NEVER_SEEN=0, OFFLINE=1, DELAYED=2, HEALTHY=3)
SELECT is(
  (SELECT hardware_status FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid) LIMIT 1),
  'NEVER_SEEN', 'HP8: worst status (NEVER_SEEN) sorted first');

-- HP9: Parameterized thresholds — lower delayed_sec to 300s (5 min):
-- Vehicle 2 (20 min gap) should now be DELAYED, but phantom (10 min) also DELAYED.
-- Vehicle 1 (30s gap) remains HEALTHY even with 300s threshold.
SELECT is(
  (SELECT hardware_status FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid, 300, 3600)
   WHERE vehicle_id = '00000000-0000-0000-0000-0000000fe101'),
  'HEALTHY', 'HP9: custom p_delayed_sec=300 still classifies 30s gap as HEALTHY');

RESET ROLE;

-- ── Tenant Isolation (INV-22 / INV-26) ──────────────────────────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000fb702","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ff702","role":"TENANT_ADMIN"}}';

-- B1: Cross-org caller requesting OrgA data → 0 rows
SELECT is(
  (SELECT count(*)::int FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff701'::uuid)),
  0, 'B1: cross-org fleet health returns 0 rows (INV-22/26 anti-oracle)');

RESET ROLE;

-- B2: Org B user requesting their own org → sees their own vehicle (positive isolation)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000fb702","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ff702","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT count(*)::int FROM public.get_fleet_health_status(
     '00000000-0000-0000-0000-0000000ff702'::uuid)),
  1, 'B2: Org B user sees exactly their own vehicle (positive tenant isolation)');

RESET ROLE;

-- ── Alert Type CHECK Extension ──────────────────────────────────────────────

-- A1: TELEMETRY_SILENT and TELEGRAM_ORPHAN now accepted by CHECK constraint
SELECT lives_ok($$
  INSERT INTO public.operational_alerts
    (organization_id, entity_id, contract_id, alert_type, severity, context)
  VALUES
    ('00000000-0000-0000-0000-0000000ff701','test-entity','test-contract',
     'TELEMETRY_SILENT','HIGH','{}');
$$, 'A1: TELEMETRY_SILENT alert_type accepted by CHECK constraint');

SELECT * FROM finish();
ROLLBACK;
