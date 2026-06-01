-- =============================================================================
-- pgTAP Test: CSV idempotent batch-upsert RPCs (Bloco 1D)
-- Migration: 20260730000002_csv_batch_upsert_rpcs.sql
-- =============================================================================
-- Validates:
--   1. All 5 RPCs exist.
--   2. All 5 are SECURITY INVOKER (NOT definer) — RLS enforced for caller (INV-2).
--   3. EXECUTE granted to authenticated.
--   4. Idempotency on external_id: re-running the same row UPDATEs, no duplicate.
--   5. Natural-key fallback when external_id is NULL.
--   6. Cross-tenant guard: authenticated caller whose JWT org != p_org_id is
--      rejected with SQLSTATE 42501 (INV-1 / INV-22).
--
-- Write paths run as postgres (RLS bypass; auth.jwt() NULL → tenant guard
-- permits the trusted backend path). The cross-tenant guard is exercised as
-- the authenticated role with a mismatched JWT claim.
-- =============================================================================

BEGIN;
SELECT plan(13);

-- ── Seed tenants (self-contained; rolled back) ───────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Org A', 'Org A SA', '00000000000191',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'a@a.com', 'EXT_A', 'LOGISTICS', ARRAY['a.com']),
  ('00000000-0000-0000-0000-000000000002', 'Org B', 'Org B SA', '00000000000272',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'b@b.com', 'EXT_B', 'TRANSPORT', ARRAY['b.com'])
ON CONFLICT (id) DO NOTHING;

-- ── 1. Function existence ─────────────────────────────────────────────────────

SELECT has_function('public', 'batch_upsert_vehicles',
  ARRAY['uuid','jsonb'], '1a: batch_upsert_vehicles exists');
SELECT has_function('public', 'batch_upsert_drivers',
  ARRAY['uuid','jsonb'], '1b: batch_upsert_drivers exists');
SELECT has_function('public', 'batch_upsert_contractors',
  ARRAY['uuid','jsonb'], '1c: batch_upsert_contractors exists');
SELECT has_function('public', 'batch_upsert_contracts',
  ARRAY['uuid','jsonb'], '1d: batch_upsert_contracts exists');
SELECT has_function('public', 'batch_upsert_operational_zones',
  ARRAY['uuid','jsonb'], '1e: batch_upsert_operational_zones exists');

-- ── 2. SECURITY INVOKER (prosecdef = false) for all 5 ─────────────────────────

SELECT is(
  (SELECT bool_and(NOT prosecdef) FROM pg_proc
   WHERE proname IN (
     'batch_upsert_vehicles','batch_upsert_drivers','batch_upsert_contractors',
     'batch_upsert_contracts','batch_upsert_operational_zones'
   )),
  true,
  '2/INV-2: all batch_upsert RPCs are SECURITY INVOKER'
);

-- ── 3. EXECUTE granted to authenticated ───────────────────────────────────────

SELECT ok(
  has_function_privilege('authenticated',
    'public.batch_upsert_vehicles(uuid, jsonb)', 'EXECUTE'),
  '3/INV-DATA-API-GRANT: authenticated may EXECUTE batch_upsert_vehicles'
);

-- ── 4. Idempotency on external_id (vehicles) ──────────────────────────────────

SELECT is(
  public.batch_upsert_vehicles(
    '00000000-0000-0000-0000-000000000001',
    '[{"external_id":"ERP-V1","plate":"AAA-0001","capacity":40,"status":"available"}]'::jsonb
  ),
  1,
  '4a: first upsert affects 1 row'
);

SELECT is(
  public.batch_upsert_vehicles(
    '00000000-0000-0000-0000-000000000001',
    '[{"external_id":"ERP-V1","plate":"AAA-9999","capacity":50,"status":"available"}]'::jsonb
  ),
  1,
  '4b: re-running same external_id affects 1 row (UPDATE)'
);

SELECT is(
  (SELECT count(*)::int FROM public.vehicles
   WHERE organization_id = '00000000-0000-0000-0000-000000000001'
     AND external_id = 'ERP-V1'),
  1,
  '4c/INV-16: no duplicate — external_id is idempotent; plate updated in place'
);

SELECT is(
  (SELECT plate FROM public.vehicles
   WHERE organization_id = '00000000-0000-0000-0000-000000000001'
     AND external_id = 'ERP-V1'),
  'AAA-9999',
  '4d: second upsert overwrote the mutable field'
);

-- ── 5. Natural-key fallback when external_id is NULL (vehicles) ───────────────

SELECT public.batch_upsert_vehicles(
  '00000000-0000-0000-0000-000000000001',
  '[{"plate":"BBB-2222","capacity":30,"status":"available"}]'::jsonb
);
SELECT public.batch_upsert_vehicles(
  '00000000-0000-0000-0000-000000000001',
  '[{"plate":"BBB-2222","capacity":33,"status":"maintenance"}]'::jsonb
);

SELECT is(
  (SELECT count(*)::int FROM public.vehicles
   WHERE organization_id = '00000000-0000-0000-0000-000000000001'
     AND plate = 'BBB-2222'),
  1,
  '5/INV-16: external_id-less rows dedup on natural key (organization_id, plate)'
);

-- ── 6. Cross-tenant guard (authenticated, mismatched JWT org) ─────────────────

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000002"}}';

SELECT throws_ok(
  $$ SELECT public.batch_upsert_vehicles(
       '00000000-0000-0000-0000-000000000001',
       '[{"external_id":"ERP-X","plate":"ZZZ-0000","capacity":1}]'::jsonb
     ) $$,
  '42501',
  NULL,
  '6/INV-1+INV-22: caller whose JWT org != p_org_id is rejected (anti cross-tenant write)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
