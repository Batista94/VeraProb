BEGIN;
SELECT plan(4);

-- Setup
INSERT INTO organizations (id, name) VALUES ('c0000000-0000-0000-0000-000000000001', 'Org C');
INSERT INTO webhook_endpoints (id, organization_id, url, is_active) VALUES ('c1000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'https://example.com/c', true);
ALTER TABLE sla_audit_ledger_v2 DISABLE TRIGGER trg_enqueue_verdict_webhooks;
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc) VALUES ('c2000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys', '{}', now());
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc) VALUES ('c2000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys', '{}', now());
ALTER TABLE sla_audit_ledger_v2 ENABLE TRIGGER trg_enqueue_verdict_webhooks;

-- Setup
-- Skipping DELETE as we are using unique IDs for tests

-- Case 1: First Failure
INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status)
VALUES ('c3000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', '{}', 'DELIVERING');

SELECT lives_ok(
    $$ SELECT webhook_delivery_fail('c3000000-0000-0000-0000-000000000001', 'HTTP_500') $$,
    'First failure call succeeds'
);

SELECT results_eq(
    $$ SELECT status, attempt_count, last_error, (next_attempt_at > now()) FROM webhook_delivery_logs WHERE id = 'c3000000-0000-0000-0000-000000000001' $$,
    $$ VALUES ('FAILED'::webhook_delivery_status, 1, 'HTTP_500'::text, true) $$,
    'Status should be FAILED, attempt 1, next_attempt_at in the future'
);

-- Case 2: Exhaustion
INSERT INTO webhook_delivery_logs (id, organization_id, endpoint_id, ledger_entry_id, event_type, payload, status, attempt_count)
VALUES ('c3000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', 'VERDICT_SEALED', '{}', 'DELIVERING', 7);

SELECT lives_ok(
    $$ SELECT webhook_delivery_fail('c3000000-0000-0000-0000-000000000002', 'HTTP_500') $$,
    'Exhaustion failure call succeeds'
);

SELECT results_eq(
    $$ SELECT status, attempt_count, next_attempt_at FROM webhook_delivery_logs WHERE id = 'c3000000-0000-0000-0000-000000000002' $$,
    $$ VALUES ('DEAD'::webhook_delivery_status, 8, NULL::timestamptZ) $$,
    'Status should be DEAD, attempt 8, next_attempt_at NULL'
);

SELECT * FROM finish();
ROLLBACK;
