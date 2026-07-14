-- =============================================================================
-- pgTAP: 20260923000005_notification_outbox_unified_view
-- CIA: C — security_invoker + channel + tenant isolation
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

SELECT has_view('public', 'notification_outbox', 'notification_outbox view exists');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'notification_outbox'
      AND c.relkind = 'v'
      AND 'security_invoker=true' = ANY (c.reloptions)
  ),
  'notification_outbox has security_invoker=true'
);

SELECT has_column('public', 'notification_outbox', 'channel',
  'channel column present');

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code, plan_type, max_vehicles,
  max_active_contracts, tool_cost_cents, dwell_time_seconds, billing_day,
  contact_email, external_id, organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000000c5a1', 'Org Outbox A', 'Org Outbox A SA',
   '0000000000c5a1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'outbox-a@test.com', 'EXT_C5A', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-00000000c5a2', 'Org Outbox B', 'Org Outbox B SA',
   '0000000000c5a2', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'outbox-b@test.com', 'EXT_C5B', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.webhook_endpoints (id, organization_id, url) VALUES
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-00000000c5a1',
   'https://outbox-a.test/hook'),
  ('00000000-0000-0000-0000-00000000c502', '00000000-0000-0000-0000-00000000c5a2',
   'https://outbox-b.test/hook')
ON CONFLICT (id) DO NOTHING;

-- Non-terminal ledger types avoid enqueue trigger phantoms (same pattern as webhook tests)
INSERT INTO public.sla_audit_ledger_v2 (id, organization_id, type, occurred_at_utc, payload) VALUES
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-00000000c5a1',
   'OCCURRENCE_REGISTERED', NOW(), '{}'),
  ('00000000-0000-0000-0000-00000000c512', '00000000-0000-0000-0000-00000000c5a1',
   'OCCURRENCE_REGISTERED', NOW(), '{}'),
  ('00000000-0000-0000-0000-00000000c513', '00000000-0000-0000-0000-00000000c5a2',
   'OCCURRENCE_REGISTERED', NOW(), '{}')
ON CONFLICT DO NOTHING;

INSERT INTO public.webhook_delivery_logs
  (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status)
VALUES (
  '00000000-0000-0000-0000-00000000c5d1',
  '00000000-0000-0000-0000-00000000c5a1',
  '00000000-0000-0000-0000-00000000c501',
  '00000000-0000-0000-0000-00000000c511',
  'EVT_C5', '{}', 'PENDING'
) ON CONFLICT DO NOTHING;

INSERT INTO public.carrier_notification_outbox
  (id, organization_id, ledger_entry_id, carrier_email, event_type, verdict_outcome, fine_cents)
VALUES (
  '00000000-0000-0000-0000-00000000c521',
  '00000000-0000-0000-0000-00000000c5a1',
  '00000000-0000-0000-0000-00000000c512',
  'carrier-a@test.com', 'SANCTION', 'PENDING_REVIEW', 0
) ON CONFLICT DO NOTHING;

INSERT INTO public.webhook_delivery_logs
  (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status)
VALUES (
  '00000000-0000-0000-0000-00000000c5d2',
  '00000000-0000-0000-0000-00000000c5a2',
  '00000000-0000-0000-0000-00000000c502',
  '00000000-0000-0000-0000-00000000c513',
  'EVT_C5B', '{}', 'PENDING'
) ON CONFLICT DO NOTHING;

SELECT ok(
  (SELECT count(*)::int FROM public.notification_outbox
    WHERE organization_id = '00000000-0000-0000-0000-00000000c5a1'
      AND channel IN ('webhook', 'email')) = 2
  AND
  (SELECT count(DISTINCT channel)::int FROM public.notification_outbox
    WHERE organization_id = '00000000-0000-0000-0000-00000000c5a1') = 2,
  'org A has webhook + email channels in notification_outbox'
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c5b1","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c5a1","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT count(*)::int FROM public.notification_outbox
    WHERE organization_id = '00000000-0000-0000-0000-00000000c5a1'),
  2,
  'authenticated org A sees own outbox rows'
);

SELECT is(
  (SELECT count(*)::int FROM public.notification_outbox
    WHERE organization_id = '00000000-0000-0000-0000-00000000c5a2'),
  0,
  'authenticated org A cannot see org B outbox (INV-22)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
