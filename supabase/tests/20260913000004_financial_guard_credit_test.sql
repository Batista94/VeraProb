-- =============================================================================
-- pgTAP: Financial Guard P4/6 — Dispute Reversal Credit
-- Migration: 20260913000004_financial_guard_credit.sql
-- Plan:      forensic_records/plans/20260913000004_financial_guard_credit_test_plan.md
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name) VALUES
  ('f4000000-0000-0000-0000-00000000000a', 'FG Credit Org');

INSERT INTO public.contracts (id, organization_id, name, contractor_name,
    valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
VALUES
  ('f4000000-0000-0000-0000-00000000c001', 'f4000000-0000-0000-0000-00000000000a',
   'FG K1 cap 100k', 'Ctr', now(), now() + interval '1 year', 'active', 100000),
  ('f4000000-0000-0000-0000-00000000c002', 'f4000000-0000-0000-0000-00000000000a',
   'FG K2 cap 20k',  'Ctr', now(), now() + interval '1 year', 'active', 20000),
  ('f4000000-0000-0000-0000-00000000c003', 'f4000000-0000-0000-0000-00000000000a',
   'FG K3 uncapped', 'Ctr', now(), now() + interval '1 year', 'active', NULL),
  ('f4000000-0000-0000-0000-00000000c004', 'f4000000-0000-0000-0000-00000000000a',
   'FG K4 drift',    'Ctr', now(), now() + interval '1 year', 'active', 100000);

-- Sanctions: engine (P3) accrues; trg_auto_enqueue_sanction creates queue rows
-- (ledger_entry_id UNIQUE — queue ids fetched via subquery below).
-- e001: 30000 on K1 | e002: 50000 on K1 | e003: 30000→applied 20000 on K2 (cap)
-- e004: 10000 on K3 (uncapped, guard inactive) | e005: 40000 on K4 (drift setup)
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES
  ('f4e00000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f4000000-0000-0000-0000-00000000c001',
   '{"verdict_evidence":{"fine_cents":30000}}'),
  ('f4e00000-0000-0000-0000-000000000002', 'f4000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f4000000-0000-0000-0000-00000000c001',
   '{"verdict_evidence":{"fine_cents":50000}}'),
  ('f4e00000-0000-0000-0000-000000000003', 'f4000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f4000000-0000-0000-0000-00000000c002',
   '{"verdict_evidence":{"fine_cents":30000}}'),
  ('f4e00000-0000-0000-0000-000000000004', 'f4000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f4000000-0000-0000-0000-00000000c003',
   '{"verdict_evidence":{"fine_cents":10000}}'),
  ('f4e00000-0000-0000-0000-000000000005', 'f4000000-0000-0000-0000-00000000000a',
   now(), 'SANCTION_RECOMMENDED', 'f4000000-0000-0000-0000-00000000c004',
   '{"verdict_evidence":{"fine_cents":40000}}');

-- ── 1: precondition — K1 accrued 80000 ───────────────────────────────────────
SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c001'),
  80000::bigint, 'precondition: K1 accrual = 30000 + 50000');

-- ── 2-3: #11 DISPUTE_ACCEPTED credits the 50000 sanction ─────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000001',
        'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000002')));

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c001'),
  30000::bigint, '#11 DISPUTE_ACCEPTED returns 50000 headroom');

SELECT is(
  (SELECT credited_cents FROM public.financial_guard_credits
   WHERE sanction_ledger_entry_id = 'f4e00000-0000-0000-0000-000000000002'),
  50000::bigint, 'credit marker recorded with post-cut value');

-- ── 4-5: #20 exactly-once — duplicate event, no double credit ────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000002',
        'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000002')));

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c001'),
  30000::bigint, '#20 second event for same sanction: accrual unchanged');

SELECT is(
  (SELECT count(*)::int FROM public.financial_guard_credits
   WHERE sanction_ledger_entry_id = 'f4e00000-0000-0000-0000-000000000002'),
  1, '#20 exactly one credit marker');

-- ── 6-7: VERDICT_REFUSED credits (user decision — fine never billed) ─────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000003',
        'f4000000-0000-0000-0000-00000000000a', now(), 'VERDICT_REFUSED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000001')));

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c001'),
  0::bigint, 'VERDICT_REFUSED returns 30000 headroom (accrual = 0)');

SELECT is(
  (SELECT credited_cents FROM public.financial_guard_credits
   WHERE sanction_ledger_entry_id = 'f4e00000-0000-0000-0000-000000000001'),
  30000::bigint, 'VERDICT_REFUSED credit marker recorded');

-- ── 8-10: OVERTURNED / RETRACTED do NOT credit (fine stands) ─────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000004',
        'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_OVERTURNED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000002')));

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c001'),
  0::bigint, 'DISPUTE_OVERTURNED does not touch accrual');

SELECT is(
  (SELECT count(*)::int FROM public.financial_guard_credits
   WHERE organization_id = 'f4000000-0000-0000-0000-00000000000a'),
  2, 'DISPUTE_OVERTURNED adds no credit marker');

INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000005',
        'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_RETRACTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000002')));

SELECT is(
  (SELECT count(*)::int FROM public.financial_guard_credits
   WHERE organization_id = 'f4000000-0000-0000-0000-00000000000a'),
  2, 'DISPUTE_RETRACTED adds no credit marker');

-- ── 11-12: truncated sanction credits POST-CUT value, not original ───────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000006',
        'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000003')));

SELECT is(
  (SELECT credited_cents FROM public.financial_guard_credits
   WHERE sanction_ledger_entry_id = 'f4e00000-0000-0000-0000-000000000003'),
  20000::bigint, 'truncated sanction credits applied 20000, never original 30000');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c002'),
  0::bigint, 'K2 accrual back to zero after truncated credit');

-- ── 13-15: guard-inactive gate (uncapped contract) — legitimate no-op ────────
SELECT lives_ok(
  format($q$INSERT INTO public.sla_audit_ledger_v2
      (id, organization_id, occurred_at_utc, type, payload)
    VALUES ('f4d00000-0000-0000-0000-000000000007',
            'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
            jsonb_build_object('queue_entry_id', %L::uuid))$q$,
    (SELECT id FROM public.sanction_review_queue
     WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000004')),
  'guard-inactive original: dispute resolution not blocked');

SELECT is(
  (SELECT count(*)::int FROM public.financial_guard_credits
   WHERE sanction_ledger_entry_id = 'f4e00000-0000-0000-0000-000000000004'),
  0, 'guard-inactive original: no credit marker');

SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c003'),
  0, 'guard-inactive original: no accrual row materialized');

-- ── 16: absent queue_entry_id (legacy/synthetic row) — fail-closed no-op ─────
SELECT lives_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (id, organization_id, occurred_at_utc, type, payload)
    VALUES ('f4d00000-0000-0000-0000-000000000008',
            'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
            '{"snapshot_id":"deadbeef-0000-0000-0000-000000000000"}')$$,
  'absent queue_entry_id: no-op, no error, no credit');

-- ── 17: #21 dangling queue_entry_id — fail-fast ──────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (id, organization_id, occurred_at_utc, type, payload)
    VALUES ('f4d00000-0000-0000-0000-000000000009',
            'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
            '{"queue_entry_id":"99999999-9999-9999-9999-999999999999"}')$$,
  '23000', NULL,
  '#21 dangling queue_entry_id: integrity violation, never silent');

-- ── 18-19: floor-0 clamp emits FINANCIAL_GUARD_DRIFT ─────────────────────────
UPDATE public.contract_penalty_monthly_accrual
   SET accrued_cents = 10000
 WHERE contract_id = 'f4000000-0000-0000-0000-00000000c004';

INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f4d00000-0000-0000-0000-000000000010',
        'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f4e00000-0000-0000-0000-000000000005')));

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c004'),
  0::bigint, 'floor-0: accrual clamped at zero, never negative');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_GUARD_DRIFT'
     AND payload ->> 'contract_id' = 'f4000000-0000-0000-0000-00000000c004'
     AND (payload ->> 'clamped_to_zero')::boolean),
  1, 'floor-0: FINANCIAL_GUARD_DRIFT audit event emitted');

-- ── 20: cap_reached_at_utc NEVER cleared by credits (INV-18) ─────────────────
SELECT ok(
  (SELECT cap_reached_at_utc IS NOT NULL
   FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f4000000-0000-0000-0000-00000000c002'),
  'historical breach stays latched after accrual returns to zero');

-- ── 21-22: queue exists but sanction ledger row missing → no-op + DRIFT ─────
-- (a RAISE would make the dispute unresolvable; credit stays fail-closed)
INSERT INTO public.sanction_review_queue
    (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence)
VALUES ('f4900000-0000-0000-0000-000000000001',
        'f4000000-0000-0000-0000-00000000000a',
        'f4900000-0000-0000-0000-00000000dead', 'FG-SET',
        'f4000000-0000-0000-0000-00000000c001', '{"fine_cents":1234}');

SELECT lives_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (id, organization_id, occurred_at_utc, type, payload)
    VALUES ('f4d00000-0000-0000-0000-000000000011',
            'f4000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
            '{"queue_entry_id":"f4900000-0000-0000-0000-000000000001"}')$$,
  'missing original sanction row: dispute resolution not blocked');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_GUARD_DRIFT' AND severity = 'critical'
     AND payload ->> 'missing_sanction_ledger_entry_id'
         = 'f4900000-0000-0000-0000-00000000dead'),
  1, 'missing original sanction row: CRITICAL drift event emitted');

SELECT * FROM finish();
ROLLBACK;
