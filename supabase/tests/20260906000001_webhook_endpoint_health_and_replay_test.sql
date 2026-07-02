BEGIN;

-- 1. Setup
SELECT plan(8);

-- Seed data
INSERT INTO public.organizations (id, name, cnpj) VALUES ('88888888-8888-8888-8888-888888888888', 'Org 1', '88888888888888');
INSERT INTO public.organizations (id, name, cnpj) VALUES ('99999999-9999-9999-9999-999999999999', 'Org 2', '99999999999999');

INSERT INTO public.webhook_endpoints (id, organization_id, url) VALUES
  ('11111111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', 'https://org1.com/webhook'),
  ('22222222-2222-2222-2222-222222222222', '99999999-9999-9999-9999-999999999999', 'https://org2.com/webhook');

-- Ledger type OCCURRENCE_REGISTERED is deliberately NON-terminal: it does NOT match the
-- enqueue_verdict_webhooks trigger filter (VERDICT_SEALED/REFUSED/DISPUTE_*/SANCTION_ACKNOWLEDGED),
-- so seeding these rows produces ZERO phantom webhook_delivery_logs. The test controls every log.
INSERT INTO public.sla_audit_ledger_v2 (id, organization_id, type, occurred_at_utc, payload) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '88888888-8888-8888-8888-888888888888', 'OCCURRENCE_REGISTERED', NOW(), '{}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '88888888-8888-8888-8888-888888888888', 'OCCURRENCE_REGISTERED', NOW(), '{}'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '99999999-9999-9999-9999-999999999999', 'OCCURRENCE_REGISTERED', NOW(), '{}');

-- Org 1 endpoint 1 carries three logs: one per replayable/terminal status.
-- 4a4… (DEAD) exists so the rate-limit assertion can target a DISTINCT still-replayable log
-- after 1a1… has already been consumed (kicking the endpoint).
INSERT INTO public.webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status) VALUES
  ('1a111111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EVT1', '{}', 'FAILED'),
  ('2a222222-2222-2222-2222-222222222222', '88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'EVT2', '{}', 'SUCCESS'),
  ('4a444444-4444-4444-4444-444444444444', '88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EVT3', '{}', 'DEAD'),
  ('3a333333-3333-3333-3333-333333333333', '99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'EVT1', '{}', 'FAILED');

-- Impersonate TENANT_ADMIN of Org 1
SELECT set_config('request.jwt.claims', '{"app_metadata": {"org_id": "88888888-8888-8888-8888-888888888888", "role": "TENANT_ADMIN"}}', true);
SET ROLE authenticated;

-- Test View Rollup (per-status counts) and Tenant Isolation
SELECT results_eq(
  'SELECT total_logs::int, failed_count::int, success_count::int, dead_count::int FROM public.v_webhook_endpoint_health WHERE id = ''11111111-1111-1111-1111-111111111111''',
  $$VALUES (3, 1, 1, 1)$$,
  'View correctly rolls up FAILED/SUCCESS/DEAD counts for the tenant''s endpoint'
);

SELECT is_empty(
  'SELECT id FROM public.v_webhook_endpoint_health WHERE id = ''22222222-2222-2222-2222-222222222222''',
  'Tenant cannot see other org''s endpoint health (security_invoker + RLS)'
);

-- Test RPC Status Validation (SUCCESS cannot be replayed)
SELECT throws_matching(
  $$ SELECT public.webhook_manual_replay('2a222222-2222-2222-2222-222222222222'); $$,
  'FAILED ou DEAD',
  'Replay rejects non-FAILED/DEAD logs'
);

-- Test RPC Tenant Isolation (Org 1 trying to replay Org 2's log → anti-oracle 404)
SELECT throws_matching(
  $$ SELECT public.webhook_manual_replay('3a333333-3333-3333-3333-333333333333'); $$,
  'Webhook delivery log not found',
  'Replay enforces anti-oracle not-found for wrong org (INV-26)'
);

-- Test RPC Success (FAILED → PENDING, kicks endpoint)
SELECT lives_ok(
  $$ SELECT public.webhook_manual_replay('1a111111-1111-1111-1111-111111111111'); $$,
  'Replay succeeds for FAILED log in own org'
);

-- Verify log status was reset to PENDING
SELECT results_eq(
  'SELECT status FROM public.webhook_delivery_logs WHERE id = ''1a111111-1111-1111-1111-111111111111''',
  $$VALUES ('PENDING'::webhook_delivery_status)$$,
  'Log status is reset to PENDING'
);

-- Verify endpoint last_kick_at was set (rate-limit lock engaged)
SELECT is_empty(
  'SELECT id FROM public.webhook_endpoints WHERE id = ''11111111-1111-1111-1111-111111111111'' AND last_kick_at IS NULL',
  'Endpoint last_kick_at is updated'
);

-- Test Rate Limiting: a DISTINCT still-replayable log (DEAD) on the same endpoint is blocked
-- because the endpoint was just kicked (< 30s ago) by the successful replay above.
SELECT throws_matching(
  $$ SELECT public.webhook_manual_replay('4a444444-4444-4444-4444-444444444444'); $$,
  'Limite de reprocessamento',
  'Second replay on the same endpoint within 30 seconds is rate limited'
);

SELECT * FROM finish();
ROLLBACK;
