-- =============================================================================
-- pgTAP: Financial Guard P6/6 — Reconciliation
-- Migration: 20260913000006_financial_guard_reconcile.sql
-- Plan:      forensic_records/plans/20260913000006_financial_guard_reconcile_test_plan.md
-- Unaccounted-row fixture: real lock contention is impossible in a single
-- pgTAP session (dblink blocked on supabase local), and toggling the trigger
-- via ALTER TABLE segfaults PG inside a transaction on the partitioned
-- parent. Equivalent state with zero DDL: a fine inserted while the contract
-- was capless (passthrough — no accrual, no cap_month_utc key), then the cap
-- set directly on contracts. Reconcile treats it exactly like a deferred row
-- (occurred_at bucket, fine never accrued). Parallel contention: P2 harness.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name) VALUES
  ('f6000000-0000-0000-0000-00000000000a', 'FG Reconcile Org');

INSERT INTO public.contracts (id, organization_id, name, contractor_name,
    valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
VALUES ('f6000000-0000-0000-0000-00000000c001',
        'f6000000-0000-0000-0000-00000000000a',
        'FG Reconcile Contract', 'Ctr', now(), now() + interval '1 year',
        'active', NULL);

-- Unaccounted fine: capless passthrough (no accrual row, no guard keys) —
-- the same accounting hole a 55P03 deferred row leaves.
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f6e00000-0000-0000-0000-000000000002',
        'f6000000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f6000000-0000-0000-0000-00000000c001',
        '{"verdict_evidence":{"fine_cents":30000}}');

-- Cap activated directly (bypasses the amend-RPC seed on purpose — the gap
-- must exist for reconcile to close).
UPDATE public.contracts
   SET monthly_penalty_cap_cents = 100000
 WHERE id = 'f6000000-0000-0000-0000-00000000c001';

-- Guard-processed debit: accrues 20000.
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f6e00000-0000-0000-0000-000000000001',
        'f6000000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f6000000-0000-0000-0000-00000000c001',
        '{"verdict_evidence":{"fine_cents":20000}}');

-- ── 1-3: surface + permissions ───────────────────────────────────────────────
SELECT has_function('public', 'reconcile_financial_guard', ARRAY['uuid'],
  'reconcile_financial_guard(uuid) exists');

SELECT ok(has_function_privilege('service_role',
  'public.reconcile_financial_guard(uuid)', 'EXECUTE'),
  'service_role EXECUTE (explicit re-grant after REVOKE PUBLIC)');

SELECT ok(NOT has_function_privilege('authenticated',
  'public.reconcile_financial_guard(uuid)', 'EXECUTE'),
  'authenticated has NO execute (service-only maintenance surface)');

-- ── 4-7: #18 deferred true-up ────────────────────────────────────────────────
SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001'),
  20000::bigint, 'precondition: only the guarded debit accrued');

SELECT is(
  public.reconcile_financial_guard('f6000000-0000-0000-0000-00000000000a'),
  1, '#18 one correction reported for the unaccounted fine');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001'),
  50000::bigint, '#18 unaccounted fine trued-up into the accumulator (20000+30000)');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_GUARD_DRIFT' AND severity = 'critical'
     AND source = 'financial_guard_reconcile'
     AND payload ->> 'contract_id' = 'f6000000-0000-0000-0000-00000000c001'),
  1, '#18 drift correction sealed in the audit log');

-- ── 8-9: idempotent second run ───────────────────────────────────────────────
SELECT is(
  public.reconcile_financial_guard('f6000000-0000-0000-0000-00000000000a'),
  0, 'second run: zero corrections (byte-identical state, INV-15)');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001'),
  50000::bigint, 'second run: accumulator untouched');

-- ── 10-11: synthetic drift corrected ─────────────────────────────────────────
UPDATE public.contract_penalty_monthly_accrual
   SET accrued_cents = 99
 WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001';

SELECT is(
  public.reconcile_financial_guard('f6000000-0000-0000-0000-00000000000a'),
  1, 'tampered accumulator detected');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001'),
  50000::bigint, 'tampered accumulator restored from ledger truth');

-- ── 12-14: credits are part of the expected formula ──────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, payload)
VALUES ('f6d00000-0000-0000-0000-000000000001',
        'f6000000-0000-0000-0000-00000000000a', now(), 'DISPUTE_ACCEPTED',
        jsonb_build_object('queue_entry_id',
          (SELECT id FROM public.sanction_review_queue
           WHERE ledger_entry_id = 'f6e00000-0000-0000-0000-000000000001')));

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001'),
  30000::bigint, 'credit applied by trigger (50000 − 20000)');

SELECT is(
  public.reconcile_financial_guard('f6000000-0000-0000-0000-00000000000a'),
  0, 'reconcile agrees with credited state (no false drift)');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f6000000-0000-0000-0000-00000000c001'),
  30000::bigint, 'credited accumulator preserved');

-- ── 15: client roles cannot invoke ───────────────────────────────────────────
-- Asserted via the privilege catalog, not a live denied call: on this local
-- supabase image, an EXECUTE-denied function call under SET ROLE segfaults
-- the backend (signal 11 — reproduced with a trivial SECURITY DEFINER probe;
-- environment bug, not project code). Catalog truth is equivalent.
SELECT ok(NOT has_function_privilege('anon',
  'public.reconcile_financial_guard(uuid)', 'EXECUTE'),
  'anon has NO execute either (maintenance surface fully closed to clients)');

SELECT * FROM finish();
ROLLBACK;
