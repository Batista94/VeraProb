-- =============================================================================
-- pgTAP (standing): Financial Guard — NO_SHOW_PENALTY coverage
--
-- No timestamp prefix: this is a standing regression test with NO paired
-- migration (the guard was delivered in 20260913000003). It proves the trigger
-- WHEN clause covers NO_SHOW_PENALTY exactly as it does SANCTION_RECOMMENDED —
-- guarded accrual, truncation + breach, legacy passthrough, and anti-forgery.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name, clock_drift_tolerance_s) VALUES
  ('face0000-0000-0000-0000-0000000000a0', 'FG NoShow Org', 300);

INSERT INTO public.contracts (id, organization_id, name, contractor_name,
    valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
VALUES
  ('face0000-0000-0000-0000-0000000000c1', 'face0000-0000-0000-0000-0000000000a0',
   'FG NoShow cap 50k', 'Ctr', now(), now() + interval '2 years', 'active', 50000);

-- ── 1-3: guarded NO_SHOW_PENALTY under cap ───────────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('face0000-0000-0000-0000-0000000000e1',
        'face0000-0000-0000-0000-0000000000a0', now(), 'NO_SHOW_PENALTY',
        'face0000-0000-0000-0000-0000000000c1',
        '{"verdict_evidence":{"fine_cents":30000}}');

SELECT is(
  (SELECT (payload -> 'verdict_evidence' ->> 'fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'face0000-0000-0000-0000-0000000000e1'),
  30000::bigint, '#1 NO_SHOW_PENALTY under cap: applied fine = original (WHEN covers type)');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'face0000-0000-0000-0000-0000000000e1'),
  false, '#1 under cap: cap_truncated = false');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'face0000-0000-0000-0000-0000000000c1'),
  30000::bigint, '#1 under cap: accrual = 30000');

-- ── 4-8: second NO_SHOW_PENALTY truncates + latches the breach ───────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('face0000-0000-0000-0000-0000000000e2',
        'face0000-0000-0000-0000-0000000000a0', now(), 'NO_SHOW_PENALTY',
        'face0000-0000-0000-0000-0000000000c1',
        '{"verdict_evidence":{"fine_cents":30000}}');

SELECT is(
  (SELECT (payload -> 'verdict_evidence' ->> 'fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'face0000-0000-0000-0000-0000000000e2'),
  20000::bigint, '#2 truncated: applied = remaining 20000');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'face0000-0000-0000-0000-0000000000e2'),
  true, '#2 truncated: cap_truncated = true');

SELECT is(
  (SELECT (payload ->> 'original_fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'face0000-0000-0000-0000-0000000000e2'),
  30000::bigint, '#2 truncated: original 30000 sealed (INV-18 fact intact)');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'face0000-0000-0000-0000-0000000000c1'),
  50000::bigint, '#2 truncated: accrual saturated at cap');

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
   WHERE type = 'FINANCIAL_CAP_REACHED'
     AND contract_id = 'face0000-0000-0000-0000-0000000000c1'),
  1, '#2 truncated: exactly one FINANCIAL_CAP_REACHED companion row');

-- ── 9-10: legacy passthrough (penalty_amount_cents, no verdict_evidence) ─────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('face0000-0000-0000-0000-0000000000e3',
        'face0000-0000-0000-0000-0000000000a0', now(), 'NO_SHOW_PENALTY',
        'face0000-0000-0000-0000-0000000000c1',
        '{"penalty_amount_cents":50000}');

SELECT is(
  (SELECT payload FROM public.sla_audit_ledger_v2
   WHERE id = 'face0000-0000-0000-0000-0000000000e3'),
  '{"penalty_amount_cents":50000}'::jsonb,
  '#3 legacy passthrough: payload byte-exact (no fine key → no guard mutation)');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'face0000-0000-0000-0000-0000000000c1'),
  50000::bigint, '#3 legacy passthrough: accrual unchanged');

-- ── 11: anti-forgery — legacy shape carrying forged guard keys is scrubbed ───
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('face0000-0000-0000-0000-0000000000e4',
        'face0000-0000-0000-0000-0000000000a0', now(), 'NO_SHOW_PENALTY',
        'face0000-0000-0000-0000-0000000000c1',
        '{"penalty_amount_cents":50000,"original_fine_cents":1,"cap_truncated":true,"cap_check_deferred":true,"cap_month_utc":"1999-01-01","cap_remaining_before_cents":99}');

SELECT is(
  (SELECT payload FROM public.sla_audit_ledger_v2
   WHERE id = 'face0000-0000-0000-0000-0000000000e4'),
  '{"penalty_amount_cents":50000}'::jsonb,
  '#4 anti-forgery: forged guard keys stripped from legacy passthrough');

SELECT * FROM finish();
ROLLBACK;
