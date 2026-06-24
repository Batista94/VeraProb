-- =============================================================================
-- Test: Sprint B — Contract Financial Amendments (append-only, INV-3/4/15/22)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(12);

-- ── Estrutura ────────────────────────────────────────────────────────────────
SELECT has_table('public', 'contract_financial_amendments', 'tabela existe');
SELECT col_type_is('public', 'contract_financial_amendments', 'penalty_multiplier_bps', 'integer', 'bps e INT (INV-4)');
SELECT col_type_is('public', 'contract_financial_amendments', 'financial_ceiling_cents', 'bigint', 'ceiling e BIGINT cents (INV-4)');
SELECT has_trigger('public', 'contract_financial_amendments', 'trg_cfa_append_only', 'trigger append-only existe');

-- ── Grants least-privilege: escrita client-side revogada ─────────────────────
SELECT table_privs_are('public', 'contract_financial_amendments', 'authenticated',
  ARRAY['SELECT'], 'authenticated: somente SELECT (escrita via RPC SECURITY DEFINER)');
SELECT table_privs_are('public', 'contract_financial_amendments', 'service_role',
  ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
  'service_role: ALL explicito (licao REVOKE FROM PUBLIC)');

-- ── Seed ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name, status) VALUES
  ('dddd0000-0000-4000-8000-00000000000a', 'Org A CFA', 'ACTIVE'),
  ('dddd0000-0000-4000-8000-00000000000b', 'Org B CFA', 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO public.contract_financial_amendments
  (id, organization_id, contract_id, financial_ceiling_cents,
   penalty_multiplier_bps, effective_at_utc, amended_by_user_id, notes)
VALUES
  ('dddd0000-0000-4000-8000-0000000000f1', 'dddd0000-0000-4000-8000-00000000000a',
   'dddd0000-0000-4000-8000-0000000000ca', 1000000, 12000, now(),
   'dddd0000-0000-4000-8000-0000000000ad', 'seed');

-- ── 7-8. Append-only (INV-3): UPDATE e DELETE bloqueados p/ qualquer role ────
SELECT throws_ok(
  $$ UPDATE public.contract_financial_amendments
     SET penalty_multiplier_bps = 99999
     WHERE id = 'dddd0000-0000-4000-8000-0000000000f1' $$,
  'P0001', 'INV-3: contract_financial_amendments is append-only',
  'UPDATE em amendment -> trigger bloqueia'
);

SELECT throws_ok(
  $$ DELETE FROM public.contract_financial_amendments
     WHERE id = 'dddd0000-0000-4000-8000-0000000000f1' $$,
  'P0001', 'INV-3: contract_financial_amendments is append-only',
  'DELETE em amendment -> trigger bloqueia'
);

-- ── 9-10. Constraints de dados ───────────────────────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.contract_financial_amendments
       (organization_id, contract_id, penalty_multiplier_bps,
        effective_at_utc, amended_by_user_id)
     VALUES ('dddd0000-0000-4000-8000-00000000000a', 'c-x', 10000,
             now() - INTERVAL '1 day', 'dddd0000-0000-4000-8000-0000000000ad') $$,
  '23514', NULL,
  'effective_at_utc retroativo -> chk_cfa_no_backdate bloqueia (INV-15)'
);

SELECT throws_ok(
  $$ INSERT INTO public.contract_financial_amendments
       (organization_id, contract_id, penalty_multiplier_bps,
        effective_at_utc, amended_by_user_id)
     VALUES ('dddd0000-0000-4000-8000-00000000000a', 'c-x', -5,
             now(), 'dddd0000-0000-4000-8000-0000000000ad') $$,
  '23514', NULL,
  'bps negativo -> chk_cfa_penalty_multiplier bloqueia (INV-4)'
);

-- ── 11-12. RLS (INV-22): Org A enxerga; Org B isolada ────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"dddd0000-0000-4000-8000-00000000000a","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT count(*) FROM public.contract_financial_amendments
   WHERE id = 'dddd0000-0000-4000-8000-0000000000f1'),
  1::bigint,
  'Org A enxerga o proprio amendment via RLS'
);

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"dddd0000-0000-4000-8000-00000000000b","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT count(*) FROM public.contract_financial_amendments
   WHERE id = 'dddd0000-0000-4000-8000-0000000000f1'),
  0::bigint,
  'Org B NAO enxerga amendment da Org A (tenant isolation)'
);

SELECT * FROM finish();
ROLLBACK;
