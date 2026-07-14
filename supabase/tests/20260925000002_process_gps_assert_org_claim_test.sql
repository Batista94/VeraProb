-- =============================================================================
-- pgTAP: 20260925000002_process_gps_assert_org_claim
-- CIA: I — SYSTEM_AUTO_START runtime on v2 + assert_org_claim in body
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(4);

SELECT ok(
  position('assert_org_claim' in pg_get_functiondef(
    'public.process_gps_for_execution_transitions(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) > 0,
  'process_gps body calls assert_org_claim'
);

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-00000000c7a1', 'Org GPS AutoStart', 'Org GPS AutoStart SA',
  '0000000000c7a1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
  'gps-autostart@test.com', 'EXT_C7', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.operational_zones (id, organization_id, name, latitude, longitude, radius_meters)
VALUES (
  '00000000-0000-0000-0000-00000000c701',
  '00000000-0000-0000-0000-00000000c7a1',
  'Origin-GPS-Start', -23.5505, -46.6333, 200
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.vehicles (
  id, organization_id, plate, device_serial, status, created_at
) VALUES (
  '00000000-0000-0000-0000-00000000c7b1',
  '00000000-0000-0000-0000-00000000c7a1',
  'CIA7A11',
  'DEV-CIA-C7',
  'available',
  NOW()
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.plan_declarations
  (id, contract_id, declared_at_utc, declared_by_user_id, plan_version,
   original_file_hash, organization_id)
VALUES (
  '00000000-0000-0000-0000-00000000c702',
  '00000000-0000-0000-0000-00000000c7c1',
  NOW(), 'gps-seed', 1, repeat('b', 64),
  '00000000-0000-0000-0000-00000000c7a1'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contractual_service_executions
  (set_id, plan_declaration_id, organization_id,
   scheduled_start_time_utc, scheduled_end_time_utc,
   start_latitude, start_longitude, start_radius_meters,
   end_latitude, end_longitude, end_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier, origin_zone_id)
VALUES (
  'cia-gps-start-1',
  '00000000-0000-0000-0000-00000000c702',
  '00000000-0000-0000-0000-00000000c7a1',
  NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '2 hours',
  -23.5505, -46.6333, 200,
  -23.5600, -46.6400, 100,
  150000, 1.5,
  '00000000-0000-0000-0000-00000000c701'
) ON CONFLICT (set_id) DO NOTHING;

INSERT INTO public.execution_states
  (id, set_id, contract_id, plan_version, organization_id,
   start_latitude, start_longitude, start_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier,
   window_start_utc, window_end_utc, status,
   created_at_utc, last_evaluated_at_utc, status_last_updated_at_utc,
   planned_vehicle_id)
VALUES (
  '00000000-0000-0000-0000-00000000c7e1',
  'cia-gps-start-1',
  '00000000-0000-0000-0000-00000000c7c1',
  1,
  '00000000-0000-0000-0000-00000000c7a1',
  -23.5505, -46.6333, 200,
  150000, 1.5,
  NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '2 hours',
  'planned',
  NOW(), NOW(), NOW(),
  '00000000-0000-0000-0000-00000000c7b1'
) ON CONFLICT (id) DO NOTHING;

SELECT lives_ok(
  $$ SELECT public.process_gps_for_execution_transitions(
       '00000000-0000-0000-0000-00000000c7a1'::uuid,
       'DEV-CIA-C7',
       -23.5505::double precision,
       -46.6333::double precision,
       NULL
     ) $$,
  'process_gps lives for planned→start inside origin zone'
);

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-00000000c7a1'
      AND set_id = 'cia-gps-start-1'
      AND type = 'SYSTEM_AUTO_START'),
  1,
  'SYSTEM_AUTO_START written once to sla_audit_ledger_v2'
);

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger
    WHERE set_id = 'cia-gps-start-1'
      AND type::text = 'SYSTEM_AUTO_START'),
  0,
  'SYSTEM_AUTO_START absent from legacy sla_audit_ledger v1'
);

SELECT * FROM finish();
ROLLBACK;
