BEGIN;
SELECT plan(8);

-- Setup
INSERT INTO organizations (id, name) VALUES ('a0000000-0000-0000-0000-000000000001', 'Org A');
INSERT INTO organizations (id, name) VALUES ('b0000000-0000-0000-0000-000000000001', 'Org B');

-- Valid Endpoint A
INSERT INTO webhook_endpoints (id, organization_id, url, is_active) VALUES ('a1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'https://example.com/a', true);
-- Valid Endpoint B
INSERT INTO webhook_endpoints (id, organization_id, url, is_active) VALUES ('b1000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'https://example.com/b', true);

-- Add some ledger entries to satisfy constraints (disable trigger to prevent auto logs)
ALTER TABLE sla_audit_ledger_v2 DISABLE TRIGGER trg_enqueue_verdict_webhooks;
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc) 
VALUES ('a2000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys', '{}', now()),
       ('a2000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys', '{}', now()),
       ('a2000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys', '{}', now()),
       ('b2000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys', '{}', now());
ALTER TABLE sla_audit_ledger_v2 ENABLE TRIGGER trg_enqueue_verdict_webhooks;

-- Clean any auto-generated logs first
-- Skipping DELETE as we are using unique IDs for tests

-- Case 1: Basic claim
INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status)
VALUES ('a3000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', '{}', 'PENDING');

-- Test 1: Drain works and sets lease
SELECT results_eq(
    $$ SELECT id FROM drain_pending_webhooks(NULL::uuid, 10) $$,
    $$ VALUES ('a3000000-0000-0000-0000-000000000001'::uuid) $$,
    'Drain should return the pending log'
);

SELECT results_eq(
    $$ SELECT status, (next_attempt_at > now()) AS has_lease FROM webhook_delivery_logs WHERE id = 'a3000000-0000-0000-0000-000000000001' $$,
    $$ VALUES ('DELIVERING'::webhook_delivery_status, true) $$,
    'Status should be DELIVERING and lease should be set'
);

-- Case 2: Crash recovery (lease expired vs in flight)
INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status, next_attempt_at)
VALUES ('a3000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000002', 'VERDICT_SEALED', '{}', 'DELIVERING', now() - interval '1 minute'),
       ('a3000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000003', 'VERDICT_SEALED', '{}', 'DELIVERING', now() + interval '5 minutes');

SELECT results_eq(
    $$ SELECT id FROM drain_pending_webhooks(NULL::uuid, 10) $$,
    $$ VALUES ('a3000000-0000-0000-0000-000000000002'::uuid) $$,
    'Drain should reclaim the expired lease log and ignore the in-flight one'
);

-- Case 3: V3 Key Revoked
INSERT INTO webhook_signing_keys (id, organization_id, version, status) VALUES ('b4000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 1, 'revoked');
INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status)
VALUES ('b3000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', '{}', 'PENDING');

-- Clean audit log
DELETE FROM system_audit_log;

SELECT results_eq(
    $$ SELECT id FROM drain_pending_webhooks('b0000000-0000-0000-0000-000000000001'::uuid, 10) $$,
    $$ SELECT id FROM webhook_delivery_logs WHERE false $$,
    'Drain should return 0 rows for revoked key'
);

SELECT results_eq(
    $$ SELECT status, last_error FROM webhook_delivery_logs WHERE id = 'b3000000-0000-0000-0000-000000000001' $$,
    $$ VALUES ('DEAD'::webhook_delivery_status, 'KEY_REVOKED'::text) $$,
    'Log should be set to DEAD due to revoked key'
);

SELECT results_eq(
    $$ SELECT event_type FROM system_audit_log WHERE severity = 'critical' $$,
    $$ VALUES ('KEY_REVOKED'::text) $$,
    'Audit log should be recorded for KEY_REVOKED'
);

-- Case 4: V5 Org Mismatch
ALTER TABLE webhook_delivery_logs DISABLE TRIGGER USER;
-- Simulate bypass
INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status)
VALUES ('b3000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', '{}', 'PENDING');
ALTER TABLE webhook_delivery_logs ENABLE TRIGGER USER;

DELETE FROM system_audit_log;

SELECT results_eq(
    $$ SELECT id FROM drain_pending_webhooks('a0000000-0000-0000-0000-000000000001'::uuid, 10) WHERE id = 'b3000000-0000-0000-0000-000000000002' $$,
    $$ SELECT id FROM webhook_delivery_logs WHERE false $$,
    'Drain should skip org mismatched endpoint'
);

SELECT results_eq(
    $$ SELECT event_type FROM system_audit_log WHERE severity = 'critical' AND event_type = 'CORRUPTION' $$,
    $$ VALUES ('CORRUPTION'::text) $$,
    'Audit log should be recorded for CORRUPTION'
);

SELECT * FROM finish();
ROLLBACK;
