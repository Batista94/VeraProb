-- =============================================================================
-- pgTAP: 20260925000001_wire_assert_org_claim_execution_rpcs
-- CIA: C+I — assert_org_claim wired into execution DEFINER RPCs (INV-1/22/26)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

SELECT ok(
  position('assert_org_claim' in pg_get_functiondef(
    'public.check_and_close_execution_autonomously(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) > 0,
  'closer body calls assert_org_claim'
);

SELECT ok(
  position('assert_org_claim' in pg_get_functiondef(
    'public.complete_execution(uuid, text, text)'::regprocedure
  )) > 0,
  'complete_execution body calls assert_org_claim'
);

SELECT ok(
  position('assert_org_claim' in pg_get_functiondef(
    'public.start_transit_for_execution(uuid, text)'::regprocedure
  )) > 0,
  'start_transit_for_execution body calls assert_org_claim'
);

SELECT ok(
  position('assert_org_claim' in pg_get_functiondef(
    'public.check_execution_compliance(uuid, text)'::regprocedure
  )) > 0,
  'check_execution_compliance body calls assert_org_claim'
);

-- JWT org A + closer(org B) → 42501 not found (INV-26)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c501","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c6a1"}}';

SELECT throws_ok(
  $$ SELECT public.check_and_close_execution_autonomously(
       '00000000-0000-0000-0000-00000000c6a2'::uuid,
       'cia-assert-set-x',
       -23.5505::double precision,
       -46.6333::double precision,
       NULL
     ) $$,
  '42501',
  'not found',
  'JWT org A + closer(org B) → 42501 before any close'
);

RESET ROLE;
RESET request.jwt.claims;

-- Null JWT (postgres) still allows closer for dwell seed
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-00000000c5a1', 'Org Assert CIA', 'Org Assert CIA SA',
  '0000000000c5a1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
  'assert-cia@test.com', 'EXT_C5', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.operational_zones (id, organization_id, name, latitude, longitude, radius_meters)
VALUES (
  '00000000-0000-0000-0000-00000000c501',
  '00000000-0000-0000-0000-00000000c5a1',
  'Dest-CIA-Assert', -23.5505, -46.6333, 100
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.plan_declarations
  (id, contract_id, declared_at_utc, declared_by_user_id, plan_version,
   original_file_hash, organization_id)
VALUES (
  '00000000-0000-0000-0000-00000000c502',
  '00000000-0000-0000-0000-00000000c5c1',
  NOW(), 'assert-seed', 1, repeat('a', 64),
  '00000000-0000-0000-0000-00000000c5a1'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contractual_service_executions
  (set_id, plan_declaration_id, organization_id,
   scheduled_start_time_utc, scheduled_end_time_utc,
   start_latitude, start_longitude, start_radius_meters,
   end_latitude, end_longitude, end_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier, destination_zone_id)
VALUES (
  'cia-assert-set-1',
  '00000000-0000-0000-0000-00000000c502',
  '00000000-0000-0000-0000-00000000c5a1',
  NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '2 hours',
  -23.5600, -46.6400, 100,
  -23.5505, -46.6333, 100,
  150000, 1.5,
  '00000000-0000-0000-0000-00000000c501'
) ON CONFLICT (set_id) DO NOTHING;

INSERT INTO public.execution_states
  (id, set_id, contract_id, plan_version, organization_id,
   start_latitude, start_longitude, start_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier,
   window_start_utc, window_end_utc, status,
   created_at_utc, last_evaluated_at_utc, status_last_updated_at_utc,
   destination_zone_entered_at_utc)
VALUES (
  '00000000-0000-0000-0000-00000000c5e1',
  'cia-assert-set-1',
  '00000000-0000-0000-0000-00000000c5c1',
  1,
  '00000000-0000-0000-0000-00000000c5a1',
  -23.5600, -46.6400, 100,
  150000, 1.5,
  NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '2 hours',
  'inTransit',
  NOW(), NOW(), NOW(),
  NOW() - INTERVAL '400 seconds'
) ON CONFLICT (id) DO NOTHING;

SELECT lives_ok(
  $$ SELECT public.check_and_close_execution_autonomously(
       '00000000-0000-0000-0000-00000000c5a1',
       'cia-assert-set-1',
       -23.5505::double precision,
       -46.6333::double precision,
       NULL
     ) $$,
  'null JWT closer lives for dwell-complete seed'
);

SELECT * FROM finish();
ROLLBACK;
