BEGIN;

SELECT plan(3);

-- Fixture setup
INSERT INTO public.organizations (id, name, cnpj) VALUES
  ('00000000-0000-0000-0000-000000000010'::uuid, 'Test Tenant - Service Role Cleanup', '10101010101010')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue (organization_id, ledger_entry_id, set_id, contract_id, status, verdict_evidence) VALUES
  ('00000000-0000-0000-0000-000000000010'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid, 'setA', 'contract_a1', 'applied',  '{"fine_cents": 5000}'::jsonb);

-- ── JWT context: service_role ────────────────────────────────────────────────
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- TC1: service_role bypass isolation check (INV-2)
SELECT is(
  (public.get_financial_impact_summary('00000000-0000-0000-0000-000000000010'::uuid) ->> 'protected_revenue_cents')::BIGINT,
  5000::BIGINT,
  'TC1: service_role access allows cross-tenant query bypass'
);

-- TC2: test_cleanup_forensic_data cleans sanction_review_queue via vera.authorized_test_cleanup
SELECT lives_ok(
  $$ SELECT public.test_cleanup_forensic_data('00000000-0000-0000-0000-000000000010'::uuid) $$,
  'TC2: test_cleanup_forensic_data executes without restriction violation'
);

-- TC3: Verify deletion
SELECT is(
  (SELECT COUNT(*) FROM public.sanction_review_queue WHERE organization_id = '00000000-0000-0000-0000-000000000010'::uuid)::INT,
  0::INT,
  'TC3: sanction_review_queue row was successfully deleted'
);

SELECT * FROM finish();
ROLLBACK;
