-- pr_scanner: ignore-regression (companion test for 20260822000001)
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- =============================================================================
-- pgTAP: fix_financial_impact_security_bypass companion test
-- Migration: 20260822000001_fix_financial_impact_security_bypass.sql
-- Focus: Verify that JWT-claims-based tenant isolation is enforced correctly
--        for TC4 (IDOR), TC8 (anon JWT), TC9 (empty app_metadata).
-- INV-2, INV-22.
-- =============================================================================

INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('cc000000-0000-0000-0000-000000000010'::uuid, 'Sec Fix Org A', '22222222222201'),
  ('cc000000-0000-0000-0000-000000000011'::uuid, 'Sec Fix Org B', '22222222222202')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (organization_id, ledger_entry_id, set_id, contract_id, status, verdict_evidence)
VALUES
  ('cc000000-0000-0000-0000-000000000010'::uuid,
   'cc000000-0000-0000-0000-000000000001'::uuid,
   'secset', 'sec-contract', 'applied', '{"fine_cents": 1000}'::jsonb);

-- TC4: IDOR — Tenant A JWT calling with Tenant B org_id (INV-2, INV-22)
SELECT set_config('request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"org_id":"cc000000-0000-0000-0000-000000000010","role":"TENANT_ADMIN"}}',
  true);
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary('cc000000-0000-0000-0000-000000000011'::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC4: IDOR blocked — Tenant A JWT cannot access Tenant B data (INV-2/INV-22)'
);

-- TC8: anon JWT (no app_metadata) — must be denied
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary('cc000000-0000-0000-0000-000000000010'::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC8: Anon JWT without org_id blocked (INV-2)'
);

-- TC9: authenticated JWT with empty app_metadata (no org_id) — must be denied
SELECT set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{}}', true);
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary('cc000000-0000-0000-0000-000000000010'::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC9: Empty app_metadata blocked (INV-2)'
);

SELECT * FROM finish();
ROLLBACK;
