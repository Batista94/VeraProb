BEGIN;
SELECT plan(10);

-- Setup
SET LOCAL search_path = public;

-- Verify table and columns exist
SELECT has_table('webhook_delivery_logs');
SELECT has_column('webhook_delivery_logs', 'payload');

-- Insert prerequisites
INSERT INTO organizations (id, name, type, "domain", status) VALUES ('33333333-3333-3333-3333-333333333333', 'Org C', 'B2B', 'c.com', 'active');
INSERT INTO webhook_endpoints (id, organization_id, url) VALUES ('e3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'https://example.com');
-- Create a minimal ledger entry (sla_audit_ledger_v2) - assuming minimal required fields exist or bypassing if complicated. Let's create one.
-- Depending on schema, we might need a snapshot and queue entry. Let's try to insert directly or skip complex fk if possible.
-- If ledger_entry_id has FK, we must insert. 
INSERT INTO submission_queue (id, organization_id, driver_id, infraction_id, created_at) VALUES ('q3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', gen_random_uuid(), gen_random_uuid(), now());
INSERT INTO sla_audit_ledger_v2 (id, organization_id, queue_entry_id, fact_type, payload, occurred_at_utc) VALUES ('l3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'q3333333-3333-3333-3333-333333333333', 'VERDICT_SEALED', '{}', now());
INSERT INTO webhook_signing_keys (id, organization_id, version, status) VALUES ('k3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 1, 'active');

-- Test Constraints and Immutability
SELECT lives_ok(
    $$
    INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload)
    VALUES ('d3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333', 'l3333333-3333-3333-3333-333333333333', 'VERDICT_SEALED', '{"test":1}');
    $$,
    'Can insert delivery log'
);

SELECT throws_ok(
    $$
    INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload)
    VALUES (gen_random_uuid(), '33333333-3333-3333-3333-333333333333', 'e3333333-3333-3333-3333-333333333333', 'l3333333-3333-3333-3333-333333333333', 'VERDICT_SEALED', '{"test":2}');
    $$,
    '23505',
    NULL,
    'Cannot insert duplicate idempotent log'
);

SELECT throws_ok(
    $$
    UPDATE webhook_delivery_logs SET payload = '{"test":3}' WHERE id = 'd3333333-3333-3333-3333-333333333333';
    $$,
    'P0001',
    'webhook_delivery_logs is append-only: payload and forensic relations cannot be updated',
    'Cannot update payload (Immutability)'
);

SELECT lives_ok(
    $$
    UPDATE webhook_delivery_logs SET signing_key_id = 'k3333333-3333-3333-3333-333333333333', status = 'DELIVERING' WHERE id = 'd3333333-3333-3333-3333-333333333333';
    $$,
    'Can update signing_key_id from NULL and status'
);

SELECT throws_ok(
    $$
    UPDATE webhook_delivery_logs SET signing_key_id = gen_random_uuid() WHERE id = 'd3333333-3333-3333-3333-333333333333';
    $$,
    'P0001',
    'webhook_delivery_logs: signing_key_id can only be set once',
    'Cannot update signing_key_id if already set'
);

SELECT throws_ok(
    $$
    DELETE FROM webhook_delivery_logs WHERE id = 'd3333333-3333-3333-3333-333333333333';
    $$,
    'P0001',
    'webhook_delivery_logs is append-only: DELETE is forbidden',
    'Cannot delete log'
);

-- Check RLS
SELECT has_rls('webhook_delivery_logs');

-- Finish
SELECT * FROM finish();
ROLLBACK;
