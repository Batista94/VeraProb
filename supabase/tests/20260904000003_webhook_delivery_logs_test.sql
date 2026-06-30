BEGIN;
SELECT plan(6);

-- Setup

-- Verify table and columns exist
SELECT has_table('webhook_delivery_logs');
SELECT has_column('webhook_delivery_logs', 'payload');

-- Insert prerequisites
INSERT INTO organizations (id, name) VALUES ('33333333-3333-3333-3333-333333333333', 'Org C');
INSERT INTO webhook_endpoints (id, organization_id, url) VALUES ('e3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'https://example.com');
-- Trigger enqueue_verdict_webhooks will automatically create a webhook_delivery_logs entry!
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc) VALUES ('a3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'VERDICT_SEALED', 'system', '{"queue_entry_id": "b3333333-3333-3333-3333-333333333333", "snapshot_id": "c3333333-3333-3333-3333-333333333333"}', now());
INSERT INTO webhook_signing_keys (id, organization_id, version, status) VALUES ('f3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 1, 'active');

-- Test Constraints and Immutability on the auto-generated row

SELECT throws_ok(
    $$
    UPDATE webhook_delivery_logs SET payload = '{"test":3}' WHERE ledger_entry_id = 'a3333333-3333-3333-3333-333333333333';
    $$,
    '23001',
    'webhook_delivery_logs is append-only: payload and forensic relations cannot be updated',
    'Cannot update payload (Immutability)'
);

SELECT lives_ok(
    $$
    UPDATE webhook_delivery_logs SET signing_key_id = 'f3333333-3333-3333-3333-333333333333', status = 'DELIVERING' WHERE ledger_entry_id = 'a3333333-3333-3333-3333-333333333333';
    $$,
    'Can update signing_key_id from NULL and status'
);

SELECT throws_ok(
    $$
    UPDATE webhook_delivery_logs SET signing_key_id = gen_random_uuid() WHERE ledger_entry_id = 'a3333333-3333-3333-3333-333333333333';
    $$,
    '23001',
    'webhook_delivery_logs: signing_key_id can only be set once',
    'Cannot update signing_key_id if already set'
);

SELECT throws_ok(
    $$
    DELETE FROM webhook_delivery_logs WHERE ledger_entry_id = 'a3333333-3333-3333-3333-333333333333';
    $$,
    '23001',
    'webhook_delivery_logs is append-only: DELETE is forbidden',
    'Cannot delete log'
);

-- Finish
SELECT * FROM finish();
ROLLBACK;
