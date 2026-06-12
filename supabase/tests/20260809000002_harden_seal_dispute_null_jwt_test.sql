BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- ── Seeds ────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000092b1', 'Org A', 'Org A SA', '00000000000902',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'a@test.com', 'EXT_HZ_A', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000092c1',
        '00000000-0000-0000-0000-0000000092b1',
        '00000000-0000-0000-0000-0000000092aa');

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES
  ('00000000-0000-0000-0000-0000000092d1',
   '00000000-0000-0000-0000-0000000092c1',
   'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}'::jsonb, 1, 0,
   '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z');

INSERT INTO public.sla_audit_ledger_v2
  (id, organization_id, type, contract_id, plan_version, occurred_at_utc, payload)
VALUES ('00000000-0000-0000-0000-0000000092e1',
        '00000000-0000-0000-0000-0000000092b1', 'DISPUTE_OVERTURNED',
        '00000000-0000-0000-0000-0000000092aa', 0, '2026-08-09T12:00:00Z',
        '{}'::jsonb);

-- 1. NULL-JWT rejected (fail-closed). Previously this proceeded — the bypass.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated"}';

SELECT throws_ok(
  $$ SELECT public.seal_dispute_resolution_snapshot(
       '00000000-0000-0000-0000-0000000092b1',
       '00000000-0000-0000-0000-0000000092e1',
       '00000000-0000-0000-0000-0000000092aa',
       'set-1', 0, '2026-08-09T12:00:00Z',
       '00000000-0000-0000-0000-0000000092f1', 'idem-null-jwt'
     ) $$,
  '42501',
  NULL,
  'NULL-JWT (no app_metadata.org_id) seal is rejected with 42501'
);

-- 2. Cross-tenant rejected (Org B JWT sealing for Org A).
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000092b2"}}';

SELECT throws_ok(
  $$ SELECT public.seal_dispute_resolution_snapshot(
       '00000000-0000-0000-0000-0000000092b1',
       '00000000-0000-0000-0000-0000000092e1',
       '00000000-0000-0000-0000-0000000092aa',
       'set-1', 0, '2026-08-09T12:00:00Z',
       '00000000-0000-0000-0000-0000000092f1', 'idem-cross'
     ) $$,
  '42501',
  NULL,
  'cross-tenant seal is rejected with 42501'
);

-- 3. Same-tenant authenticated still works (no regression for legit callers).
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000092b1"}}';

SELECT lives_ok(
  $$ SELECT public.seal_dispute_resolution_snapshot(
       '00000000-0000-0000-0000-0000000092b1',
       '00000000-0000-0000-0000-0000000092e1',
       '00000000-0000-0000-0000-0000000092aa',
       'set-1', 0, '2026-08-09T12:00:00Z',
       '00000000-0000-0000-0000-0000000092f1', 'idem-ok'
     ) $$,
  'same-tenant authenticated seal still succeeds (no regression)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
