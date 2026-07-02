BEGIN;
SELECT plan(21);

-- ═══════════════════════════════════════════════════════════════════════════
-- Setup — one tenant, TWO carriers (contractors): A has a deliverable email,
-- B has the '@placeholder.invalid' backfill sentinel. Each carrier owns a
-- contract. The verdict's ledger.contract_id is what routes the notification.
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO organizations (id, name, contact_email)
VALUES ('55555555-5555-5555-5555-555555555555', 'Org Carrier Test', 'embarcador@org5.com');

INSERT INTO webhook_endpoints (id, organization_id, url)
VALUES ('e5555555-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'https://erp-c.example.com');

INSERT INTO dispute_reason_codes (code, category, label_pt, label_en)
VALUES ('TEST_001', 'OPERATIONAL', 'Test PT', 'Test EN')
ON CONFLICT (code) DO NOTHING;

-- Carrier A — real, deliverable email
INSERT INTO contractors (id, organization_id, name, tax_id, primary_email, contact_name)
VALUES ('c0000000-0000-0000-0000-0000000000aa', '55555555-5555-5555-5555-555555555555',
        'Carrier A', '11111111000199', 'compliance@carrier-a.com', 'Fulano A');

-- Carrier B — placeholder email (non-deliverable sentinel)
INSERT INTO contractors (id, organization_id, name, tax_id, primary_email, contact_name)
VALUES ('c0000000-0000-0000-0000-0000000000bb', '55555555-5555-5555-5555-555555555555',
        'Carrier B', '22222222000188', 'noreply@placeholder.invalid', 'Fulano B');

INSERT INTO contracts (id, organization_id, name, contractor_id, contractor_name, valid_from_utc, valid_until_utc, status)
VALUES ('d0000000-0000-0000-0000-0000000000aa', '55555555-5555-5555-5555-555555555555',
        'Contract A', 'c0000000-0000-0000-0000-0000000000aa', 'Carrier A',
        NOW() - INTERVAL '1 day', NOW() + INTERVAL '365 days', 'active');

INSERT INTO contracts (id, organization_id, name, contractor_id, contractor_name, valid_from_utc, valid_until_utc, status)
VALUES ('d0000000-0000-0000-0000-0000000000bb', '55555555-5555-5555-5555-555555555555',
        'Contract B', 'c0000000-0000-0000-0000-0000000000bb', 'Carrier B',
        NOW() - INTERVAL '1 day', NOW() + INTERVAL '365 days', 'active');

-- ── Structural sanity ────────────────────────────────────────────────────────
SELECT has_table('carrier_notification_outbox', 'carrier_notification_outbox table exists');
SELECT has_trigger('sla_audit_ledger_v2', 'trg_enqueue_verdict_webhooks', 'unified resolution trigger present');

-- ═══════════════════════════════════════════════════════════════════════════
-- Terminal verdict on Carrier A's contract → fans out to BOTH outboxes,
-- routing the carrier email from the CONTRACT'S contractor, not the tenant.
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, contract_id, payload, occurred_at_utc)
VALUES ('a1111111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555',
        'VERDICT_SEALED', 'system', 'd0000000-0000-0000-0000-0000000000aa',
        '{"reason_code":"TEST_001","verdict_evidence":{"fine_cents":125000}}', now());

SELECT is(
  (SELECT count(*)::int FROM webhook_delivery_logs WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  1, 'ERP webhook outbox: 1 row for sealed verdict');

SELECT is(
  (SELECT count(*)::int FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  1, 'Carrier outbox: 1 row for sealed verdict');

SELECT is(
  (SELECT carrier_email FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  'compliance@carrier-a.com',
  'Recipient resolved from contract''s contractor (NOT tenant contact_email)');

SELECT is(
  (SELECT fine_cents FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  125000::bigint, 'fine_cents sealed from verdict_evidence (INV-4)');

SELECT is(
  (SELECT verdict_outcome FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  'SEALED', 'verdict_outcome derived from ledger type');

-- ═══════════════════════════════════════════════════════════════════════════
-- Terminal verdict on Carrier B's contract (placeholder email) → ERP webhook
-- still fires, but NO carrier notification (Zero-Trust deliverability guard).
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, contract_id, payload, occurred_at_utc)
VALUES ('a2222222-2222-2222-2222-222222222222', '55555555-5555-5555-5555-555555555555',
        'VERDICT_REFUSED', 'system', 'd0000000-0000-0000-0000-0000000000bb',
        '{"verdict_evidence":{"fine_cents":50000}}', now());

SELECT is(
  (SELECT count(*)::int FROM carrier_notification_outbox WHERE ledger_entry_id = 'a2222222-2222-2222-2222-222222222222'),
  0, 'Placeholder carrier email skipped — no guaranteed-bounce row enqueued');

SELECT is(
  (SELECT count(*)::int FROM webhook_delivery_logs WHERE ledger_entry_id = 'a2222222-2222-2222-2222-222222222222'),
  1, 'ERP webhook still fires even when carrier email is undeliverable');

-- ── Non-terminal fact enqueues nothing ───────────────────────────────────────
INSERT INTO sla_audit_ledger_v2 (id, organization_id, type, operator_id, contract_id, payload, occurred_at_utc)
VALUES ('a3333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555',
        'EXECUTION_BOUND', 'system', 'd0000000-0000-0000-0000-0000000000aa', '{}', now());

SELECT is(
  (SELECT count(*)::int FROM carrier_notification_outbox WHERE ledger_entry_id = 'a3333333-3333-3333-3333-333333333333'),
  0, 'Non-terminal fact does not enqueue a carrier notification');

-- ── Idempotency: re-enqueue same (org, ledger, email) is a no-op ─────────────
INSERT INTO carrier_notification_outbox (organization_id, ledger_entry_id, carrier_email, event_type, verdict_outcome, fine_cents)
VALUES ('55555555-5555-5555-5555-555555555555', 'a1111111-1111-1111-1111-111111111111', 'compliance@carrier-a.com', 'VERDICT_SEALED', 'SEALED', 125000)
ON CONFLICT DO NOTHING;

SELECT is(
  (SELECT count(*)::int FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  1, 'UNIQUE(org, ledger, email) prevents duplicate enqueue');

-- ── Immutability: sealed field mutation blocked (INV-3) ──────────────────────
PREPARE mutate_sealed AS
  UPDATE carrier_notification_outbox SET fine_cents = 0
  WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111';
SELECT throws_ok('mutate_sealed', 'P0001', NULL, 'Immutability guard blocks fine_cents mutation');

-- ── Append-only: DELETE blocked (INV-3) ──────────────────────────────────────
PREPARE delete_row AS
  DELETE FROM carrier_notification_outbox
  WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111';
SELECT throws_ok('delete_row', 'P0001', NULL, 'Append-only guard blocks DELETE');

-- ═══════════════════════════════════════════════════════════════════════════
-- Drain lease — the sealed carrier row is reserved for 2 minutes so overlapping
-- drains cannot re-pick it before the dispatcher marks it SENT/FAILED.
-- ═══════════════════════════════════════════════════════════════════════════
SELECT is(
  (SELECT count(*)::int FROM public.drain_pending_carrier_notifications('55555555-5555-5555-5555-555555555555'::uuid, 20)),
  1, 'First drain reserves the pending carrier row');

SELECT is(
  (SELECT count(*)::int FROM public.drain_pending_carrier_notifications('55555555-5555-5555-5555-555555555555'::uuid, 20)),
  0, 'Second drain returns 0 — 2-minute lease prevents duplicate dispatch');

-- ── Failure path: backoff → FAILED (attempt 1 < max) ─────────────────────────
SELECT lives_ok(
  $$ SELECT public.carrier_notification_fail(
       (SELECT id FROM public.carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
       '55555555-5555-5555-5555-555555555555'::uuid, 'HTTP_429') $$,
  'carrier_notification_fail records a transient failure');

SELECT is(
  (SELECT status FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  'FAILED', 'Transient failure → FAILED with backoff');

-- ── Failure path: DEAD after max attempts ────────────────────────────────────
UPDATE carrier_notification_outbox SET attempt_count = 5
  WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111';
SELECT public.carrier_notification_fail(
  (SELECT id FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  '55555555-5555-5555-5555-555555555555'::uuid, 'HTTP_500');
SELECT is(
  (SELECT status FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  'DEAD', 'Exhausted attempts → DEAD');

-- ── Anti-oracle: fail() for the wrong org is a silent no-op (INV-1/INV-26) ────
SELECT public.carrier_notification_fail(
  (SELECT id FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  '99999999-9999-9999-9999-999999999999'::uuid, 'cross-tenant');
SELECT is(
  (SELECT status FROM carrier_notification_outbox WHERE ledger_entry_id = 'a1111111-1111-1111-1111-111111111111'),
  'DEAD', 'Wrong-org fail leaves the row untouched (no cross-tenant write)');

-- ═══════════════════════════════════════════════════════════════════════════
-- RLS tenant isolation (INV-2/INV-22) — authenticated reads only its own org.
-- ═══════════════════════════════════════════════════════════════════════════
SET LOCAL ROLE authenticated;

SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"55555555-5555-5555-5555-555555555555"}}';
SELECT is(
  (SELECT count(*)::int FROM public.carrier_notification_outbox),
  1, 'Tenant sees its own carrier notifications');

SET LOCAL request.jwt.claims = '{"role":"authenticated","app_metadata":{"org_id":"99999999-9999-9999-9999-999999999999"}}';
SELECT is(
  (SELECT count(*)::int FROM public.carrier_notification_outbox),
  0, 'Foreign tenant sees zero rows (RLS isolation)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
