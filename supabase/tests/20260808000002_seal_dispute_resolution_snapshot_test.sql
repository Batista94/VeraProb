BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- Seed organization
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'Org A', 'Org A SA', '00000000000808',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'a@test.com', 'EXT_A', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Seed contract rule set
INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES ('00000000-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-0000000000b1',
        '00000000-0000-0000-0000-0000000000aa');

-- Seed active rule version
INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc)
VALUES
  ('00000000-0000-0000-0000-0000000000d1',
   '00000000-0000-0000-0000-0000000000c1',
   'NO_SHOW_PENALTY', '{"penalty_amount_cents": 50000}'::jsonb, 2, 0,
   '2026-01-01T00:00:00Z', NULL);

-- Seed pre-existing ledger entry
INSERT INTO public.sla_audit_ledger_v2 (id, organization_id, type, contract_id, plan_version, occurred_at_utc, payload)
VALUES ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b1', 'DISPUTE_OVERTURNED', '00000000-0000-0000-0000-0000000000aa', 1, '2026-08-01T12:00:00Z', '{}'::jsonb);

-- 1. Function existence
SELECT has_function(
  'public',
  'seal_dispute_resolution_snapshot',
  ARRAY['uuid', 'uuid', 'uuid', 'text', 'integer', 'timestamp with time zone', 'uuid', 'text'],
  'Function seal_dispute_resolution_snapshot exists with correct signature'
);

-- 2. Security definer (Backend Authority)
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'seal_dispute_resolution_snapshot'),
  true,
  'Function seal_dispute_resolution_snapshot is SECURITY DEFINER'
);

-- 3. Execute privilege for authenticated
SELECT ok(
  has_function_privilege('authenticated',
    'public.seal_dispute_resolution_snapshot(uuid, uuid, uuid, text, integer, timestamp with time zone, uuid, text)',
    'EXECUTE'),
  'authenticated may execute seal_dispute_resolution_snapshot'
);

-- 4. Execute privilege for service_role
SELECT ok(
  has_function_privilege('service_role',
    'public.seal_dispute_resolution_snapshot(uuid, uuid, uuid, text, integer, timestamp with time zone, uuid, text)',
    'EXECUTE'),
  'service_role may execute seal_dispute_resolution_snapshot'
);

-- 5. Happy-path execution
SELECT lives_ok(
  $$ SELECT public.seal_dispute_resolution_snapshot(
       '00000000-0000-0000-0000-0000000000b1',
       '00000000-0000-0000-0000-0000000000e1',
       '00000000-0000-0000-0000-0000000000aa',
       'set-1', 1, '2026-08-01T12:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-dispute-1'
     ) $$,
  'seal_dispute_resolution_snapshot executes successfully on happy path'
);

-- 6. Snapshot persisted and linked
SELECT is(
  (SELECT count(*)::int FROM public.forensic_evidence_snapshots
   WHERE organization_id = '00000000-0000-0000-0000-0000000000b1'
     AND ledger_entry_id = '00000000-0000-0000-0000-0000000000e1'),
  1,
  'A forensic snapshot was successfully created and linked to the existing ledger entry'
);

-- 7. Idempotency (same key returns same snapshot without duplicate)
SELECT is(
  (SELECT public.seal_dispute_resolution_snapshot(
       '00000000-0000-0000-0000-0000000000b1',
       '00000000-0000-0000-0000-0000000000e1',
       '00000000-0000-0000-0000-0000000000aa',
       'set-1', 1, '2026-08-01T12:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-dispute-1'
   ) ->> 'idempotency_key'),
  'idem-dispute-1',
  'Idempotency key replay returns the existing snapshot record'
);

-- 8. Cross-tenant check
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000000b2"}}';

SELECT throws_ok(
  $$ SELECT public.seal_dispute_resolution_snapshot(
       '00000000-0000-0000-0000-0000000000b1',
       '00000000-0000-0000-0000-0000000000e1',
       '00000000-0000-0000-0000-0000000000aa',
       'set-1', 1, '2026-08-01T12:00:00Z',
       '00000000-0000-0000-0000-0000000000f1', 'idem-dispute-evil'
     ) $$,
  '42501',
  NULL,
  'Cross-tenant seal dispute resolution snapshot execution is rejected (42501)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
