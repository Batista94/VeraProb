BEGIN;
SELECT plan(6);

-- Setup Org
INSERT INTO public.organizations (id, name, cnpj)
VALUES ('22222222-2222-2222-2222-222222222222'::uuid, 'Test Org', '12345678901234')
ON CONFLICT (id) DO NOTHING;

-- Pre-insert ledger entries required by the FK constraint:
-- FOREIGN KEY (organization_id, ledger_entry_id) REFERENCES sla_audit_ledger_v2(organization_id, id)
INSERT INTO public.sla_audit_ledger_v2 (id, organization_id, type, operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)
VALUES
  ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'VERDICT_SEALED', 'user-1', 'set-1', '33333333-3333-3333-3333-333333333333'::uuid, 0, '{}'::jsonb, NOW()),
  ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'VERDICT_SEALED', 'user-1', 'set-1', '33333333-3333-3333-3333-333333333333'::uuid, 0, '{}'::jsonb, NOW());

-- 1. Authentic Snapshot
INSERT INTO public.forensic_evidence_snapshots (
  ledger_entry_id, organization_id, queue_entry_id,
  contract_id, rule_set_id, sla_rule_version,
  idempotency_key, sealed_by,
  snapshot, integrity_hash, sealed_at_utc
) VALUES (
  '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333',
  '33333333-3333-3333-3333-333333333333'::uuid,
  '55555555-5555-5555-5555-555555555555'::uuid,
  1,
  'test-key-1',
  '66666666-6666-6666-6666-666666666666'::uuid,
  '{"key": "value"}'::jsonb,
  encode(extensions.digest(public.jsonb_canonical_text('{"key": "value"}'::jsonb), 'sha256'), 'hex'),
  NOW()
);

-- 2. Tampered Snapshot (hash doesn't match payload)
INSERT INTO public.forensic_evidence_snapshots (
  ledger_entry_id, organization_id, queue_entry_id,
  contract_id, rule_set_id, sla_rule_version,
  idempotency_key, sealed_by,
  snapshot, integrity_hash, sealed_at_utc
) VALUES (
  '44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555',
  '33333333-3333-3333-3333-333333333333'::uuid,
  '55555555-5555-5555-5555-555555555555'::uuid,
  1,
  'test-key-2',
  '66666666-6666-6666-6666-666666666666'::uuid,
  '{"key": "tampered"}'::jsonb,
  encode(extensions.digest(public.jsonb_canonical_text('{"key": "original"}'::jsonb), 'sha256'), 'hex'),
  NOW()
);

-- Tests for verify_forensic_evidence (by ledger_entry_id)
SELECT is(
  public.verify_forensic_evidence('22222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) ->> 'status',
  'authentic',
  'verify_forensic_evidence identifies authentic snapshot'
);

SELECT is(
  (public.verify_forensic_evidence('22222222-2222-2222-2222-222222222222'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) -> 'snapshot' ->> 'organization_id')::uuid,
  '22222222-2222-2222-2222-222222222222'::uuid,
  'verify_forensic_evidence returns the full row object (TOCTOU mitigation)'
);

SELECT is(
  public.verify_forensic_evidence('22222222-2222-2222-2222-222222222222'::uuid, '44444444-4444-4444-4444-444444444444'::uuid) ->> 'status',
  'tampered',
  'verify_forensic_evidence correctly detects tampered payload'
);

-- Tests for verify_forensic_evidence_by_queue
SELECT is(
  public.verify_forensic_evidence_by_queue('22222222-2222-2222-2222-222222222222'::uuid, '33333333-3333-3333-3333-333333333333'::uuid) ->> 'status',
  'authentic',
  'verify_forensic_evidence_by_queue identifies authentic snapshot'
);

SELECT is(
  public.verify_forensic_evidence_by_queue('22222222-2222-2222-2222-222222222222'::uuid, '55555555-5555-5555-5555-555555555555'::uuid) ->> 'status',
  'tampered',
  'verify_forensic_evidence_by_queue correctly detects tampered payload'
);

-- Failures
SELECT throws_ok(
  $$SELECT public.verify_forensic_evidence('22222222-2222-2222-2222-222222222222'::uuid, '00000000-0000-0000-0000-000000000000'::uuid)$$,
  'P0002',
  'Snapshot not found for verdict 00000000-0000-0000-0000-000000000000 (Req 8/INV-26)',
  'Missing ledger_entry_id returns P0002 exception'
);

SELECT * FROM finish();
ROLLBACK;
