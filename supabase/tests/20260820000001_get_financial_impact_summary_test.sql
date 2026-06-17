BEGIN;

SELECT plan(10);

-- ── Fixture setup como superuser (bypass RLS) ─────────────────────────────────
INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('00000000-0000-0000-0000-000000000010'::uuid, 'Test Tenant A - Financial', '10101010101010'),
  ('00000000-0000-0000-0000-000000000011'::uuid, 'Test Tenant B - Financial', '11111111111111')
ON CONFLICT (id) DO NOTHING;

-- ledger_entry_id: sem FK enforçada — usar UUIDs sintéticos diretamente
INSERT INTO public.sanction_review_queue (organization_id, ledger_entry_id, set_id, contract_id, status, verdict_evidence) VALUES
  ('00000000-0000-0000-0000-000000000010'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid, 'setA', 'contract_a1', 'applied',  '{"fine_cents": 5000}'::jsonb),
  ('00000000-0000-0000-0000-000000000010'::uuid, 'a0000000-0000-0000-0000-000000000002'::uuid, 'setA', 'contract_a1', 'pending',  '{"fine_cents": 2000}'::jsonb),
  ('00000000-0000-0000-0000-000000000010'::uuid, 'a0000000-0000-0000-0000-000000000003'::uuid, 'setA', 'contract_a1', 'rejected', '{"fine_cents": 1000}'::jsonb),
  ('00000000-0000-0000-0000-000000000011'::uuid, 'b0000000-0000-0000-0000-000000000001'::uuid, 'setB', 'contract_b1', 'applied',  '{"fine_cents": 8000}'::jsonb);

-- ── JWT context: Tenant A ────────────────────────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000010","role":"TENANT_ADMIN"}}',
  true);

-- TC1: Receita Protegida Tenant A
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000010'::uuid) ->> 'protected_revenue_cents')::BIGINT,
  5000::BIGINT,
  'TC1: Tenant A protected_revenue_cents = 5000 (status applied)'
);

-- TC2: Receita em Risco Tenant A
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000010'::uuid) ->> 'revenue_at_risk_cents')::BIGINT,
  2000::BIGINT,
  'TC2: Tenant A revenue_at_risk_cents = 2000 (status pending)'
);

-- TC3: Receita Perdida Tenant A
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000010'::uuid) ->> 'lost_revenue_cents')::BIGINT,
  1000::BIGINT,
  'TC3: Tenant A lost_revenue_cents = 1000 (status rejected)'
);

-- TC4: IDOR — Tenant A claim, p_org_id = Tenant B (INV-2)
-- pgTAP throws_ok espera SQLSTATE de 5 chars ('42501' = insufficient_privilege)
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary('00000000-0000-0000-0000-000000000011'::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC4/INV-22: IDOR Tenant A→B bloqueado por INV-2'
);

-- ── JWT context: Tenant B ────────────────────────────────────────────────────
SELECT set_config('request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000011","role":"TENANT_ADMIN"}}',
  true);

-- TC5: Tenant B vê apenas seus dados
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000011'::uuid) ->> 'protected_revenue_cents')::BIGINT,
  8000::BIGINT,
  'TC5: Tenant B protected_revenue_cents = 8000 (isolado de Tenant A)'
);

-- TC6: Tenant B at_risk = 0
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000011'::uuid) ->> 'revenue_at_risk_cents')::BIGINT,
  0::BIGINT,
  'TC6: Tenant B revenue_at_risk_cents = 0 (isolado de Tenant A)'
);

-- TC7: Tenant B lost = 0
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000011'::uuid) ->> 'lost_revenue_cents')::BIGINT,
  0::BIGINT,
  'TC7: Tenant B lost_revenue_cents = 0 (isolado de Tenant A)'
);

-- TC8: Contexto anon — sem org_id
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary('00000000-0000-0000-0000-000000000010'::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC8: Contexto anon/sem org_id dispara SQLSTATE 42501'
);

-- TC9: app_metadata sem org_id
SELECT set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{}}', true);
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary('00000000-0000-0000-0000-000000000010'::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC9: app_metadata sem org_id dispara SQLSTATE 42501'
);

-- TC10: p_org_id NULL (guarda explícita na função cobre este caso)
SELECT set_config('request.jwt.claims',
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000010","role":"TENANT_ADMIN"}}',
  true);
SELECT throws_ok(
  $$ SELECT public.get_financial_impact_summary(NULL::uuid) $$,
  '42501',
  'Access denied. Tenant isolation violation (INV-2).',
  'TC10: p_org_id NULL dispara SQLSTATE 42501'
);

SELECT * FROM finish();
ROLLBACK;
