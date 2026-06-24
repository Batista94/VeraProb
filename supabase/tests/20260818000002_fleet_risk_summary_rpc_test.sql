BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- =============================================================================
-- pgTAP: get_fleet_risk_summary — Sprint C (Read Models)
-- Verifies risk_bps is computed identically to SlaBreachRiskCalculator (INV-15),
-- active-state filtering, worst-first ordering, and anti-oracle org gate.
-- NOW() is the transaction timestamp (constant in-txn), so windows expressed
-- relative to NOW() yield exact, deterministic risk_bps.
-- =============================================================================

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000fa701','OrgF','OrgF SA','000000000fa701',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'of@test.com',
   'EXTF','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.plan_declarations
  (id, contract_id, declared_at_utc, declared_by_user_id, plan_version,
   original_file_hash, organization_id)
VALUES
  ('00000000-0000-0000-0000-0000000fd701','fcontract',NOW(),'tester',1,'hash701',
   '00000000-0000-0000-0000-0000000fa701')
ON CONFLICT (id) DO NOTHING;

-- Parent CSE rows (FK target for execution_states.set_id).
INSERT INTO public.contractual_service_executions
  (set_id, plan_declaration_id, scheduled_start_time_utc, scheduled_end_time_utc,
   start_latitude, start_longitude, start_radius_meters,
   end_latitude, end_longitude, end_radius_meters,
   contractual_value_cents, no_show_penalty_multiplier)
SELECT s,'00000000-0000-0000-0000-0000000fd701',NOW(),NOW()+INTERVAL '1 hour',
       -23.5,-46.6,100,-23.6,-46.7,100,100000,1.5
FROM unnest(ARRAY['fsMID','fsEARLY','fsLATE','fsDONE','fsINH']) s
ON CONFLICT (set_id) DO NOTHING;

-- Execution states with controlled windows:
--   fsMID  (planned)   total=10000s, end=+750s  → risk_bps = 5000 (mid-buffer)
--   fsEARLY(planned)   far future               → risk_bps < 0 (safe)
--   fsLATE (inTransit) past deadline            → risk_bps > 10000 (breached)
--   fsDONE (completed) excluded
--   fsINH  (inhibited) excluded
INSERT INTO public.execution_states
  (id, set_id, contract_id, plan_version, start_latitude, start_longitude,
   start_radius_meters, contractual_value_cents, no_show_penalty_multiplier,
   window_start_utc, window_end_utc, status, created_at_utc,
   last_evaluated_at_utc, status_last_updated_at_utc, organization_id)
VALUES
  (gen_random_uuid(),'fsMID','fcontract',1,-23.5,-46.6,100,100000,1.5,
   NOW()-INTERVAL '9250 seconds', NOW()+INTERVAL '750 seconds','planned',
   NOW(),NOW(),NOW(),'00000000-0000-0000-0000-0000000fa701'),
  (gen_random_uuid(),'fsEARLY','fcontract',1,-23.5,-46.6,100,100000,1.5,
   NOW()+INTERVAL '1 hour', NOW()+INTERVAL '2 hours','planned',
   NOW(),NOW(),NOW(),'00000000-0000-0000-0000-0000000fa701'),
  (gen_random_uuid(),'fsLATE','fcontract',1,-23.5,-46.6,100,100000,1.5,
   NOW()-INTERVAL '2 hours', NOW()-INTERVAL '30 minutes','inTransit',
   NOW(),NOW(),NOW(),'00000000-0000-0000-0000-0000000fa701'),
  (gen_random_uuid(),'fsDONE','fcontract',1,-23.5,-46.6,100,100000,1.5,
   NOW()-INTERVAL '3 hours', NOW()-INTERVAL '2 hours','completed',
   NOW(),NOW(),NOW(),'00000000-0000-0000-0000-0000000fa701'),
  (gen_random_uuid(),'fsINH','fcontract',1,-23.5,-46.6,100,100000,1.5,
   NOW()-INTERVAL '3 hours', NOW()-INTERVAL '1 hour','inhibited',
   NOW(),NOW(),NOW(),'00000000-0000-0000-0000-0000000fa701');

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_function('public','get_fleet_risk_summary',ARRAY['uuid','integer'],
  'S1: get_fleet_risk_summary(uuid,int) exists');
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname='get_fleet_risk_summary'),
  true, 'S2: get_fleet_risk_summary is SECURITY DEFINER');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000fb701","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000fa701","role":"TENANT_ADMIN"}}';

-- HP1: mid-buffer window → risk_bps exactly 5000.
SELECT is(
  (SELECT risk_bps FROM public.get_fleet_risk_summary(
     '00000000-0000-0000-0000-0000000fa701', 10) WHERE set_id='fsMID'),
  5000::bigint, 'HP1: mid-buffer risk_bps = 5000 (matches calculator, INV-5/15)');

-- HP2: far-future window → negative (safe).
SELECT ok(
  (SELECT risk_bps FROM public.get_fleet_risk_summary(
     '00000000-0000-0000-0000-0000000fa701', 10) WHERE set_id='fsEARLY') < 0,
  'HP2: far-future window risk_bps < 0 (safe)');

-- HP3: past-deadline window → breached (> 10000).
SELECT ok(
  (SELECT risk_bps FROM public.get_fleet_risk_summary(
     '00000000-0000-0000-0000-0000000fa701', 10) WHERE set_id='fsLATE') > 10000,
  'HP3: past-deadline window risk_bps > 10000 (breached)');

-- HP4: completed/inhibited excluded → exactly 3 active rows.
SELECT is(
  (SELECT count(*)::int FROM public.get_fleet_risk_summary(
     '00000000-0000-0000-0000-0000000fa701', 10)),
  3, 'HP4: only active (planned/inTransit) windows ranked');

-- HP5: worst first + limit honored.
SELECT is(
  (SELECT set_id FROM public.get_fleet_risk_summary(
     '00000000-0000-0000-0000-0000000fa701', 1)),
  'fsLATE', 'HP5: worst (breached) ranked first; p_limit=1 honored');
RESET ROLE;

-- B1: cross-org caller → 0 rows.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000fb701","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000fa702","role":"TENANT_ADMIN"}}';
SELECT is(
  (SELECT count(*)::int FROM public.get_fleet_risk_summary(
     '00000000-0000-0000-0000-0000000fa701', 10)),
  0, 'B1: cross-org fleet risk returns 0 rows (INV-22/26)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
