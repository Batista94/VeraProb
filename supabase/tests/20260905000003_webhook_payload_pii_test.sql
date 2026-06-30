BEGIN;
SELECT plan(4);

-- Setup
INSERT INTO organizations (id, name) VALUES ('d0000000-0000-0000-0000-000000000001', 'Org D');
INSERT INTO webhook_endpoints (id, organization_id, url, is_active) VALUES ('d1000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'https://example.com/d', true);

-- Realistic verdict payload: EXACTLY what approve_sanction writes — the fine is sealed
-- inside verdict_evidence (INV-15), reason_code is top-level — plus PII that MUST be
-- stripped. (Not a fabricated top-level payload; that would mask the real wiring.)
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, payload, occurred_at_utc)
VALUES ('d2000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'VERDICT_SEALED', 'sys',
  jsonb_build_object(
    'queue_entry_id',      'dddddddd-0000-0000-0000-000000000001',
    'approved_by_user_id', 'user-123',
    'actor_email',         'auditor@example.com',
    'reason_code',         'SENSOR_FAULT',
    'reviewer_reason',     'ok',
    'resolution_reason',   'manual review',
    'decided_by',          'user-123',
    'placa',               'ABC1234',
    'motorista',           'Joao',
    'verdict_evidence',    jsonb_build_object('fine_cents', 12345, 'placa', 'ABC1234', 'motorista', 'Joao')
  ), now());

CREATE TEMP TABLE temp_webhook_payload AS
SELECT payload FROM webhook_delivery_logs WHERE ledger_entry_id = 'd2000000-0000-0000-0000-000000000001';

-- 1. fine_cents extracted from the SEALED verdict_evidence; outcome derived from ledger type
SELECT results_eq(
    $$ SELECT payload->'financial'->>'fine_cents', payload->'verdict'->>'outcome' FROM temp_webhook_payload $$,
    $$ VALUES ('12345', 'SEALED') $$,
    'fine_cents sourced from verdict_evidence (INV-15); outcome derived from ledger type'
);

-- 2. reason_code validated from top-level; no attachments → empty hash array
SELECT results_eq(
    $$ SELECT payload->'verdict'->>'reason_code', payload->'evidence'->>'attachment_hashes' FROM temp_webhook_payload $$,
    $$ VALUES ('SENSOR_FAULT', '[]') $$,
    'reason_code validated from top-level; attachment_hashes empty when no evidence'
);

-- 3. The verdict_evidence blob (which carries PII) must NOT be copied wholesale
SELECT results_eq(
    $$ SELECT payload ? 'verdict_evidence' FROM temp_webhook_payload $$,
    $$ VALUES (false) $$,
    'verdict_evidence blob (PII carrier) must not be copied into the webhook payload'
);

-- 4. No PII leaks at any nesting level
SELECT results_eq(
    $$ SELECT (payload ? 'placa') OR (payload ? 'motorista') OR (payload ? 'decided_by')
              OR (payload->'verdict' ? 'decided_by') OR (payload->'financial' ? 'placa')
       FROM temp_webhook_payload $$,
    $$ VALUES (false) $$,
    'Payload must NOT leak PII fields (placa, motorista, decided_by)'
);

SELECT * FROM finish();
ROLLBACK;
