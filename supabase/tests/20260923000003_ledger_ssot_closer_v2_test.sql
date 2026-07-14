-- =============================================================================
-- pgTAP: 20260923000003_ledger_ssot_closer_v2
-- CIA: I — closer writes SYSTEM_AUTO_CLOSE to v2 only (INV-3 SSOT)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

SELECT ok(
  position('sla_audit_ledger_v2' in pg_get_functiondef(
    'public.check_and_close_execution_autonomously(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) > 0,
  'closer function body references sla_audit_ledger_v2'
);

SELECT ok(
  position('INSERT INTO public.sla_audit_ledger (' in pg_get_functiondef(
    'public.check_and_close_execution_autonomously(uuid, text, double precision, double precision, timestamptz)'::regprocedure
  )) = 0,
  'closer no longer inserts into legacy sla_audit_ledger'
);

-- ── Minimal seed: zero-evidence dwell already satisfied ──────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-00000000c3a1', 'Org Closer CIA', 'Org Closer CIA SA',
  '0000000000c3a1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
  'closer-cia@test.com', 'EXT_C3', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.operational_zones (id, organization_id, name, latitude, longitude, radius_meters)
VALUES (
  '00000000-0000-0000-0000-00000000c301',
  '00000000-0000-0000-0000-00000000c3a1',
  'Dest-CIA-Closer', -23.5505, -46.6333, 100
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.plan_declarations
  (id, contract_id, declared_at_utc, declared_by_user_id, plan_version,
   original_file_hash, organization_id)
VALUES (
  '00000000-0000-0000-0000-00000000c302',
  '00000000-0000-0000-0000-00000000c3c1',
  NOW(), 'closer-seed', 1, repeat('c', 64),
  '00000000-0000-0000-0000-00000000c3a1'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contractual_service_executions
  (set_id, plan_declaration_id, organization_id,
   scheduled_start_time_utc, scheduled_end_time_utc,
   start_latitude, start_longitude, start_radius_meters,
   end_latitude, end_longitude, end_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier, destination_zone_id)
VALUES (
  'cia-closer-set-1',
  '00000000-0000-0000-0000-00000000c302',
  '00000000-0000-0000-0000-00000000c3a1',
  NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '2 hours',
  -23.5600, -46.6400, 100,
  -23.5505, -46.6333, 100,
  150000, 1.5,
  '00000000-0000-0000-0000-00000000c301'
) ON CONFLICT (set_id) DO NOTHING;

INSERT INTO public.execution_states
  (id, set_id, contract_id, plan_version, organization_id,
   start_latitude, start_longitude, start_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier,
   window_start_utc, window_end_utc, status,
   created_at_utc, last_evaluated_at_utc, status_last_updated_at_utc,
   destination_zone_entered_at_utc)
VALUES (
  '00000000-0000-0000-0000-00000000c3e1',
  'cia-closer-set-1',
  '00000000-0000-0000-0000-00000000c3c1',
  1,
  '00000000-0000-0000-0000-00000000c3a1',
  -23.5600, -46.6400, 100,
  150000, 1.5,
  NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '2 hours',
  'inTransit',
  NOW(), NOW(), NOW(),
  NOW() - INTERVAL '400 seconds'
) ON CONFLICT (id) DO NOTHING;

SELECT lives_ok(
  $$ SELECT public.check_and_close_execution_autonomously(
       '00000000-0000-0000-0000-00000000c3a1',
       'cia-closer-set-1',
       -23.5505::double precision,
       -46.6333::double precision,
       NULL
     ) $$,
  'closer RPC lives for zero-evidence dwell-complete scenario'
);

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-00000000c3a1'
      AND set_id = 'cia-closer-set-1'
      AND type = 'SYSTEM_AUTO_CLOSE'),
  1,
  'SYSTEM_AUTO_CLOSE written once to sla_audit_ledger_v2'
);

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger
    WHERE set_id = 'cia-closer-set-1'
      AND type::text = 'SYSTEM_AUTO_CLOSE'),
  0,
  'SYSTEM_AUTO_CLOSE absent from legacy sla_audit_ledger v1'
);

SELECT * FROM finish();
ROLLBACK;
