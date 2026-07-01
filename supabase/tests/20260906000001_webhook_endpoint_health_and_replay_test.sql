BEGIN;

-- 1. Setup
SELECT plan(8);

-- Seed data
INSERT INTO public.organizations (id, name, cnpj) VALUES ('88888888-8888-8888-8888-888888888888', 'Org 1', '88888888888888');
INSERT INTO public.organizations (id, name, cnpj) VALUES ('99999999-9999-9999-9999-999999999999', 'Org 2', '99999999999999');

INSERT INTO public.webhook_endpoints (id, organization_id, url) VALUES
  ('11111111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', 'https://org1.com/webhook'),
  ('22222222-2222-2222-2222-222222222222', '99999999-9999-9999-9999-999999999999', 'https://org2.com/webhook');

INSERT INTO public.sla_audit_ledger_v2 (id, organization_id, type, occurred_at_utc, payload) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '88888888-8888-8888-8888-888888888888', 'TEST', NOW(), '{}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '88888888-8888-8888-8888-888888888888', 'TEST', NOW(), '{}'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '99999999-9999-9999-9999-999999999999', 'TEST', NOW(), '{}');

-- Bypass immutability trigger for initial seed
ALTER TABLE public.webhook_delivery_logs DISABLE TRIGGER trg_webhook_delivery_logs_immutability;

INSERT INTO public.webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status) VALUES
  ('log11111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'EVT1', '{}', 'FAILED'),
  ('log22222-2222-2222-2222-222222222222', '88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'EVT2', '{}', 'SUCCESS'),
  ('log33333-3333-3333-3333-333333333333', '99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'EVT1', '{}', 'FAILED');

ALTER TABLE public.webhook_delivery_logs ENABLE TRIGGER trg_webhook_delivery_logs_immutability;

-- Impersonate TENANT_ADMIN of Org 1
SELECT set_config('request.jwt.claims', '{"app_metadata": {"org_id": "88888888-8888-8888-8888-888888888888", "role": "TENANT_ADMIN"}}', true);
SET ROLE authenticated;

-- Test View Rollup and Tenant Isolation
SELECT results_eq(
  'SELECT total_logs::int, failed_count::int, success_count::int FROM public.v_webhook_endpoint_health WHERE id = ''11111111-1111-1111-1111-111111111111''',
  $$VALUES (2, 1, 1)$$,
  'View correctly rolls up logs for the tenant''s endpoint'
);

SELECT is_empty(
  'SELECT id FROM public.v_webhook_endpoint_health WHERE id = ''22222222-2222-2222-2222-222222222222''',
  'Tenant cannot see other org''s endpoint health'
);

-- Test RPC Status Validation (SUCCESS cannot be replayed)
SELECT throws_matching(
  $$ SELECT public.webhook_manual_replay('log22222-2222-2222-2222-222222222222'); $$,
  'Can only replay FAILED or DEAD logs',
  'Replay rejects SUCCESS logs'
);

-- Test RPC Tenant Isolation (Org 1 trying to replay Org 2's log)
SELECT throws_matching(
  $$ SELECT public.webhook_manual_replay('log33333-3333-3333-3333-333333333333'); $$,
  'Webhook delivery log not found',
  'Replay enforces anti-oracle 404 for wrong org'
);

-- Test RPC Success
SELECT lives_ok(
  $$ SELECT public.webhook_manual_replay('log11111-1111-1111-1111-111111111111'); $$,
  'Replay succeeds for FAILED log in own org'
);

-- Verify log status was updated to PENDING
SELECT results_eq(
  'SELECT status FROM public.webhook_delivery_logs WHERE id = ''log11111-1111-1111-1111-111111111111''',
  $$VALUES ('PENDING'::webhook_delivery_status)$$,
  'Log status is reset to PENDING'
);

-- Verify endpoint last_kick_at was updated (rate limit lock)
SELECT is_empty(
  'SELECT id FROM public.webhook_endpoints WHERE id = ''11111111-1111-1111-1111-111111111111'' AND last_kick_at IS NULL',
  'Endpoint last_kick_at is updated'
);

-- Test Rate Limiting
SELECT throws_matching(
  $$ SELECT public.webhook_manual_replay('log11111-1111-1111-1111-111111111111'); $$,
  'Rate limit exceeded',
  'Second replay within 30 seconds is blocked'
);

SELECT * FROM finish();
ROLLBACK;
