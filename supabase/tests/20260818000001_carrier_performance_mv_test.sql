BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

-- =============================================================================
-- pgTAP: mv_carrier_performance + get_carrier_performance_ranking — Sprint C
-- Covers: MV + unique index + RPC structure, integer-bps arithmetic (INV-5),
-- MV confidentiality (no tenant grant, INV-22), and RPC anti-oracle (INV-26).
-- =============================================================================

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000ca701','OrgC','OrgC SA','000000000ca701',
   'America/Sao_Paulo','BRL','enterprise',1000,50,15000,300,15,'oc@test.com',
   'EXTC','LOGISTICS',ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- contractA: 8 executed / 10 obligations → compliance 8000 bps.
INSERT INTO public.shadow_verdicts
  (id, organization_id, set_id, contract_id, engine_verdict, engine_verdict_at_utc,
   engine_version, verdict_evidence, traceability_hash, divergence_type)
SELECT gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701','svA'||g,'contractA',
       'executed', NOW() - (g||' minutes')::interval, 'v1', '{}'::jsonb, 'hA'||g, 'match'
FROM generate_series(1,8) g;

INSERT INTO public.shadow_verdicts
  (id, organization_id, set_id, contract_id, engine_verdict, engine_verdict_at_utc,
   engine_version, verdict_evidence, traceability_hash, divergence_type)
VALUES
  (gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701','svA9','contractA',
   'noShow', NOW(), 'v1', '{}'::jsonb, 'hA9', 'false_positive'),
  (gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701','svA10','contractA',
   'evidenceGap', NOW(), 'v1', '{}'::jsonb, 'hA10', 'false_negative');

-- contractB: 10 executed / 10 → compliance 10000 bps (better; ranked last).
INSERT INTO public.shadow_verdicts
  (id, organization_id, set_id, contract_id, engine_verdict, engine_verdict_at_utc,
   engine_version, verdict_evidence, traceability_hash, divergence_type)
SELECT gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701','svB'||g,'contractB',
       'executed', NOW(), 'v1', '{}'::jsonb, 'hB'||g, 'match'
FROM generate_series(1,10) g;

-- Sanctions for contractA: 2 disputed (50000 + 30000) + 1 applied (10000)
-- → total_fine_exposure 90000; dispute_count 2; dispute_rate 2/10 = 2000 bps.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  (gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701',gen_random_uuid(),'svA1','contractA',
   '{"fine_cents":50000}'::jsonb,'disputed',NOW(),'00000000-0000-0000-0000-0000000cb701',NOW()+INTERVAL '5 days'),
  (gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701',gen_random_uuid(),'svA9','contractA',
   '{"fine_cents":30000}'::jsonb,'disputed',NOW(),'00000000-0000-0000-0000-0000000cb701',NOW()+INTERVAL '5 days'),
  (gen_random_uuid(),'00000000-0000-0000-0000-0000000ca701',gen_random_uuid(),'svA10','contractA',
   '{"fine_cents":10000}'::jsonb,'applied',NULL,NULL,NULL);

REFRESH MATERIALIZED VIEW public.mv_carrier_performance;

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_materialized_view('public','mv_carrier_performance',
  'S1: mv_carrier_performance exists');

SELECT ok(
  EXISTS(SELECT 1 FROM pg_indexes
          WHERE schemaname='public' AND indexname='uq_mv_carrier_performance'),
  'S2: unique index uq_mv_carrier_performance present (REFRESH CONCURRENTLY)');

SELECT has_function('public','get_carrier_performance_ranking',
  ARRAY['uuid','integer'], 'S3: get_carrier_performance_ranking(uuid,int) exists');

SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname='get_carrier_performance_ranking'),
  true, 'S4: get_carrier_performance_ranking is SECURITY DEFINER');

-- ── Arithmetic + ordering via the RPC (own org) ──────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000cb701","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ca701","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT compliance_rate_bps FROM public.get_carrier_performance_ranking(
     '00000000-0000-0000-0000-0000000ca701', 20)
    WHERE contract_id='contractA'),
  8000, 'HP1: compliance_rate_bps 8/10 = 8000 exact (INV-5)');

SELECT is(
  (SELECT total_fine_exposure_cents FROM public.get_carrier_performance_ranking(
     '00000000-0000-0000-0000-0000000ca701', 20)
    WHERE contract_id='contractA'),
  90000::bigint, 'HP2: total_fine_exposure_cents = SUM(fine_cents) all sanctions');

SELECT is(
  (SELECT dispute_rate_bps FROM public.get_carrier_performance_ranking(
     '00000000-0000-0000-0000-0000000ca701', 20)
    WHERE contract_id='contractA'),
  2000, 'HP3: dispute_rate_bps 2/10 = 2000 (INV-5)');

SELECT is(
  (SELECT contract_id FROM public.get_carrier_performance_ranking(
     '00000000-0000-0000-0000-0000000ca701', 20) LIMIT 1),
  'contractA', 'HP4: worst compliance (contractA 8000) ranked first');
RESET ROLE;

-- ── B2: cross-org caller → 0 rows (anti-oracle, no error) ────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000cb701","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ca702","role":"TENANT_ADMIN"}}';
SELECT is(
  (SELECT count(*)::int FROM public.get_carrier_performance_ranking(
     '00000000-0000-0000-0000-0000000ca701', 20)),
  0, 'B2: cross-org ranking returns 0 rows (INV-22/26)');
RESET ROLE;

-- ── B1: direct SELECT on the MV by authenticated → permission denied ─────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000cb701","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ca701","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT 1 FROM public.mv_carrier_performance LIMIT 1 $$,
  '42501', NULL, 'B1: direct MV SELECT by tenant denied (INV-22)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
