BEGIN;
SELECT plan(5);

-- Verify trigger exists
SELECT has_trigger('sla_audit_ledger_v2', 'trg_enqueue_verdict_webhooks');

-- Setup: org + one active endpoint
INSERT INTO organizations (id, name) VALUES ('44444444-4444-4444-4444-444444444444', 'Org D');
INSERT INTO webhook_endpoints (id, organization_id, url) VALUES
  ('e4444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'https://erp-a.example.com');

-- Terminal verdict fans out to the single active endpoint
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc)
VALUES ('a4444444-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'VERDICT_SEALED', 'system', '{"snapshot_id": "c4444444-4444-4444-4444-444444444444"}', now());

SELECT is(
  (SELECT count(*)::int FROM webhook_delivery_logs WHERE ledger_entry_id = 'a4444444-4444-4444-4444-444444444444'),
  1,
  'Single active endpoint -> exactly one delivery log'
);

SELECT is(
  (SELECT count(*)::int FROM webhook_delivery_logs
   WHERE ledger_entry_id = 'a4444444-4444-4444-4444-444444444444'
     AND status = 'PENDING' AND signing_key_id IS NULL),
  1,
  'Enqueued row is PENDING with signing_key_id NULL (frozen later by dispatcher)'
);

-- Non-terminal fact does NOT enqueue
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc)
VALUES ('a4444444-4444-4444-4444-44440000000e', '44444444-4444-4444-4444-444444444444', 'EXECUTION_BOUND', 'system', '{}', now());

SELECT is(
  (SELECT count(*)::int FROM webhook_delivery_logs WHERE ledger_entry_id = 'a4444444-4444-4444-4444-44440000000e'),
  0,
  'Non-terminal fact does not enqueue any webhook'
);

-- Second active endpoint -> next terminal verdict fans out to BOTH
INSERT INTO webhook_endpoints (id, organization_id, url) VALUES
  ('e4444444-4444-4444-4444-444444444445', '44444444-4444-4444-4444-444444444444', 'https://erp-b.example.com');

INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc)
VALUES ('a4444444-4444-4444-4444-444444444445', '44444444-4444-4444-4444-444444444444', 'DISPUTE_ACCEPTED', 'system', '{"snapshot_id": "c4444444-4444-4444-4444-444444444446"}', now());

SELECT is(
  (SELECT count(*)::int FROM webhook_delivery_logs WHERE ledger_entry_id = 'a4444444-4444-4444-4444-444444444445'),
  2,
  'Two active endpoints -> fan-out two delivery logs'
);

SELECT * FROM finish();
ROLLBACK;
