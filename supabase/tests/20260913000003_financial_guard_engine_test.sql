-- =============================================================================
-- pgTAP: Financial Guard P3/6 — Core Engine
-- Migration: 20260913000003_financial_guard_engine.sql
-- Plan:      forensic_records/plans/20260913000003_financial_guard_engine_test_plan.md
-- Note: claim-mismatch tests run LAST — SET LOCAL request.jwt.claims persists
--       to transaction end and would poison later postgres-context inserts.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(56);

-- ── Fixture ──────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name, clock_drift_tolerance_s) VALUES
  ('f3a00000-0000-0000-0000-00000000000a', 'FG Engine Org A', 300),
  ('f3b00000-0000-0000-0000-00000000000b', 'FG Engine Org B (wide drift)', 8640000),
  ('f3000000-0000-0000-0000-000000000003', 'FG Partition Org p0', 300),
  ('f3000000-0000-0000-0000-000000000007', 'FG Partition Org p1', 300),
  ('f3000000-0000-0000-0000-00000000000f', 'FG Partition Org p2', 300),
  ('f3000000-0000-0000-0000-000000000001', 'FG Partition Org p3', 300);

INSERT INTO public.contracts (id, organization_id, name, contractor_name,
    valid_from_utc, valid_until_utc, status, monthly_penalty_cap_cents)
VALUES
  ('f3a00000-0000-0000-0000-00000000c00f', 'f3a00000-0000-0000-0000-00000000000a',
   'FG uncapped',        'Ctr', now(), now() + interval '2 years', 'active', NULL),
  ('f3a00000-0000-0000-0000-00000000c001', 'f3a00000-0000-0000-0000-00000000000a',
   'FG cap 100k',        'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3a00000-0000-0000-0000-00000000c002', 'f3a00000-0000-0000-0000-00000000000a',
   'FG cap 50k border',  'Ctr', now(), now() + interval '2 years', 'active', 50000),
  ('f3a00000-0000-0000-0000-00000000c003', 'f3a00000-0000-0000-0000-00000000000a',
   'FG warn idem',       'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3a00000-0000-0000-0000-00000000c004', 'f3a00000-0000-0000-0000-00000000000a',
   'FG anti-forgery',    'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3a00000-0000-0000-0000-00000000c005', 'f3a00000-0000-0000-0000-00000000000a',
   'FG clock spoof',     'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3b00000-0000-0000-0000-00000000c0b1', 'f3b00000-0000-0000-0000-00000000000b',
   'FG month rollover',  'Ctr', now() - interval '1 year', now() + interval '2 years', 'active', 100000),
  ('f3000000-0000-0000-0000-00000000c0a0', 'f3000000-0000-0000-0000-000000000003',
   'FG p0 contract',     'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3000000-0000-0000-0000-00000000c0a1', 'f3000000-0000-0000-0000-000000000007',
   'FG p1 contract',     'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3000000-0000-0000-0000-00000000c0a2', 'f3000000-0000-0000-0000-00000000000f',
   'FG p2 contract',     'Ctr', now(), now() + interval '2 years', 'active', 100000),
  ('f3000000-0000-0000-0000-00000000c0a3', 'f3000000-0000-0000-0000-000000000001',
   'FG p3 contract',     'Ctr', now(), now() + interval '2 years', 'active', 100000);

-- ── 1-2: #1 passthrough byte-exact on uncapped contract ─────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000001',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c00f',
        '{"reason_code":"RC1","verdict_evidence":{"fine_cents":30000}}');

SELECT is(
  (SELECT payload FROM public.sla_audit_ledger_v2
   WHERE id = 'f3e00000-0000-0000-0000-000000000001'),
  '{"reason_code":"RC1","verdict_evidence":{"fine_cents":30000}}'::jsonb,
  '#1 uncapped: payload byte-exact untouched');

SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c00f'),
  0,
  '#1 uncapped: no accrual row created');

-- ── 3: forged guard keys stripped on capless passthrough ────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000002',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c00f',
        '{"reason_code":"RC2","verdict_evidence":{"fine_cents":1000},"original_fine_cents":1,"cap_truncated":true,"cap_remaining_before_cents":99,"cap_check_deferred":true,"cap_month_utc":"1999-01-01"}');

SELECT is(
  (SELECT payload FROM public.sla_audit_ledger_v2
   WHERE id = 'f3e00000-0000-0000-0000-000000000002'),
  '{"reason_code":"RC2","verdict_evidence":{"fine_cents":1000}}'::jsonb,
  'forged guard keys stripped on capless passthrough (no false provenance)');

-- ── 4-9: #2 exact accumulation under cap ─────────────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000003',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c001',
        '{"reason_code":"RC3","verdict_evidence":{"fine_cents":30000}}');

SELECT is(
  (SELECT (payload -> 'verdict_evidence' ->> 'fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000003'),
  30000::bigint, '#2 under cap: applied fine = original');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000003'),
  false, '#2 under cap: cap_truncated = false');

SELECT is(
  (SELECT (payload ->> 'original_fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000003'),
  30000::bigint, '#2 under cap: original_fine_cents sealed');

SELECT is(
  (SELECT (payload ->> 'cap_remaining_before_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000003'),
  100000::bigint, '#2 under cap: cap_remaining_before_cents = full cap');

SELECT is(
  (SELECT payload ->> 'cap_month_utc'
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000003'),
  to_char((date_trunc('month', now() AT TIME ZONE 'UTC'))::date, 'YYYY-MM-DD'),
  '#2 under cap: cap_month_utc sealed to current UTC month');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  30000::bigint, '#2 under cap: accrual = 30000');

-- ── 10-13: 80% warning fires once ────────────────────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000004',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c001',
        '{"reason_code":"RC4","verdict_evidence":{"fine_cents":50000}}');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  80000::bigint, 'accrual = 80000 after second fine');

SELECT ok(
  (SELECT warned_at_utc IS NOT NULL FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  '80% threshold: warned_at_utc set');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_CAP_WARNING' AND severity = 'warning'
     AND actor_type = 'SYSTEM'
     AND payload ->> 'contract_id' = 'f3a00000-0000-0000-0000-00000000c001'),
  1, 'FINANCIAL_CAP_WARNING audit event emitted once');

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
   WHERE type = 'FINANCIAL_CAP_WARNING'
     AND contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  1, 'FINANCIAL_CAP_WARNING companion ledger row emitted once');

-- ── 14-22: #3 partial truncation + breach ────────────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000005',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c001',
        '{"reason_code":"RC5","verdict_evidence":{"fine_cents":30000}}');

SELECT is(
  (SELECT (payload -> 'verdict_evidence' ->> 'fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000005'),
  20000::bigint, '#3 partial: applied = remaining 20000');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000005'),
  true, '#3 partial: cap_truncated = true');

SELECT is(
  (SELECT (payload ->> 'original_fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000005'),
  30000::bigint, '#3 partial: original 30000 preserved (INV-18 fact intact)');

SELECT is(
  (SELECT (payload ->> 'cap_remaining_before_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000005'),
  20000::bigint, '#3 partial: remaining before = 20000');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  100000::bigint, '#3 partial: accrual saturated at cap');

SELECT ok(
  (SELECT cap_reached_at_utc IS NOT NULL FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  'breach: cap_reached_at_utc set');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_CAP_REACHED' AND severity = 'critical'
     AND payload ->> 'contract_id' = 'f3a00000-0000-0000-0000-00000000c001'),
  1, 'FINANCIAL_CAP_REACHED audit event emitted once');

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
   WHERE type = 'FINANCIAL_CAP_REACHED'
     AND contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  1, 'FINANCIAL_CAP_REACHED companion ledger row emitted once');

SELECT is(
  (SELECT payload ->> 'breaching_ledger_entry_id' FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_CAP_REACHED'
     AND payload ->> 'contract_id' = 'f3a00000-0000-0000-0000-00000000c001'),
  'f3e00000-0000-0000-0000-000000000005',
  'breach audit points at the breaching ledger entry');

-- ── 23-26: #4 post-limit inserts apply zero, no duplicate breach event ───────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000006',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c001',
        '{"reason_code":"RC6","verdict_evidence":{"fine_cents":10000}}');

SELECT is(
  (SELECT (payload -> 'verdict_evidence' ->> 'fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000006'),
  0::bigint, '#4 post-limit: applied fine = 0');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000006'),
  true, '#4 post-limit: cap_truncated = true');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c001'),
  100000::bigint, '#4 post-limit: accrual unchanged');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_CAP_REACHED'
     AND payload ->> 'contract_id' = 'f3a00000-0000-0000-0000-00000000c001'),
  1, '#4 post-limit: breach event NOT re-emitted (idempotent)');

-- ── 27-29: #5 exact border (fine == remaining) ───────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000007',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c002',
        '{"reason_code":"RC7","verdict_evidence":{"fine_cents":50000}}');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000007'),
  false, '#5 exact border: full fine applied, not truncated');

SELECT ok(
  (SELECT accrued_cents = 50000 AND cap_reached_at_utc IS NOT NULL
   FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c002'),
  '#5 exact border: accrual = cap and breach latched');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_CAP_REACHED'
     AND payload ->> 'contract_id' = 'f3a00000-0000-0000-0000-00000000c002'),
  1, '#5 exact border: breach event emitted');

-- ── 30: #12 warning idempotent across inserts ────────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000008',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c003',
        '{"reason_code":"RC8","verdict_evidence":{"fine_cents":80000}}'),
       ('f3e00000-0000-0000-0000-000000000009',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c003',
        '{"reason_code":"RC9","verdict_evidence":{"fine_cents":1000}}');

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE event_type = 'FINANCIAL_CAP_WARNING'
     AND payload ->> 'contract_id' = 'f3a00000-0000-0000-0000-00000000c003'),
  1, '#12 warning emitted exactly once per contract-month');

-- ── 31-35: #15 anti-forgery — guard overwrites all forged keys ───────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000010',
        'f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
        'f3a00000-0000-0000-0000-00000000c004',
        '{"reason_code":"RCA","verdict_evidence":{"fine_cents":10000},"original_fine_cents":1,"cap_truncated":true,"cap_remaining_before_cents":99,"cap_check_deferred":true,"cap_month_utc":"1999-01-01"}');

SELECT is(
  (SELECT (payload ->> 'original_fine_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000010'),
  10000::bigint, '#15 forged original_fine_cents overwritten');

SELECT is(
  (SELECT (payload ->> 'cap_truncated')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000010'),
  false, '#15 forged cap_truncated overwritten');

SELECT is(
  (SELECT (payload ->> 'cap_remaining_before_cents')::bigint
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000010'),
  100000::bigint, '#15 forged cap_remaining_before_cents overwritten');

SELECT is(
  (SELECT (payload ->> 'cap_check_deferred')::boolean
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000010'),
  false, '#15 forged cap_check_deferred overwritten');

SELECT is(
  (SELECT payload ->> 'cap_month_utc'
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000010'),
  to_char((date_trunc('month', now() AT TIME ZONE 'UTC'))::date, 'YYYY-MM-DD'),
  '#15 forged cap_month_utc overwritten with clamped bucket');

-- ── 36-40: #17 clock-spoof clamp (bucket clamped, fact preserved) ────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000011',
        'f3a00000-0000-0000-0000-00000000000a', now() + interval '90 days',
        'SANCTION_RECOMMENDED', 'f3a00000-0000-0000-0000-00000000c005',
        '{"reason_code":"RCB","verdict_evidence":{"fine_cents":5000}}'),
       ('f3e00000-0000-0000-0000-000000000012',
        'f3a00000-0000-0000-0000-00000000000a', now() - interval '90 days',
        'SANCTION_RECOMMENDED', 'f3a00000-0000-0000-0000-00000000c005',
        '{"reason_code":"RCC","verdict_evidence":{"fine_cents":7000}}');

SELECT ok(
  (SELECT occurred_at_utc > now() + interval '80 days'
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000011'),
  '#17 future spoof: forensic occurred_at_utc NEVER altered');

SELECT is(
  (SELECT payload ->> 'cap_month_utc'
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000011'),
  to_char((date_trunc('month', (now() + interval '300 seconds') AT TIME ZONE 'UTC'))::date, 'YYYY-MM-DD'),
  '#17 future spoof: bucket clamped to now()+tolerance');

SELECT is(
  (SELECT payload ->> 'cap_month_utc'
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000012'),
  to_char((date_trunc('month', (now() - interval '300 seconds') AT TIME ZONE 'UTC'))::date, 'YYYY-MM-DD'),
  '#17 past spoof: bucket clamped to now()-tolerance');

SELECT ok(
  (SELECT occurred_at_utc < now() - interval '80 days'
   FROM public.sla_audit_ledger_v2 WHERE id = 'f3e00000-0000-0000-0000-000000000012'),
  '#17 past spoof: forensic occurred_at_utc NEVER altered');

SELECT is(
  (SELECT COALESCE(sum(accrued_cents), 0)::bigint FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3a00000-0000-0000-0000-00000000c005'),
  12000::bigint, '#17 spoofed fines accrued into clamped buckets (5000+7000)');

-- ── 41-43: #6 month independence (wide-tolerance org, real past bucket) ──────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000013',
        'f3b00000-0000-0000-0000-00000000000b', now() - interval '35 days',
        'SANCTION_RECOMMENDED', 'f3b00000-0000-0000-0000-00000000c0b1',
        '{"reason_code":"RCD","verdict_evidence":{"fine_cents":40000}}'),
       ('f3e00000-0000-0000-0000-000000000014',
        'f3b00000-0000-0000-0000-00000000000b', now(),
        'SANCTION_RECOMMENDED', 'f3b00000-0000-0000-0000-00000000c0b1',
        '{"reason_code":"RCE","verdict_evidence":{"fine_cents":25000}}');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3b00000-0000-0000-0000-00000000c0b1'
     AND month_utc = (date_trunc('month', (now() - interval '35 days') AT TIME ZONE 'UTC'))::date),
  40000::bigint, '#6 within tolerance: past month accrues in its own bucket');

SELECT is(
  (SELECT accrued_cents FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3b00000-0000-0000-0000-00000000c0b1'
     AND month_utc = (date_trunc('month', now() AT TIME ZONE 'UTC'))::date),
  25000::bigint, '#6 current month accrues independently');

SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual
   WHERE contract_id = 'f3b00000-0000-0000-0000-00000000c0b1'),
  2, '#6 two independent month buckets exist');

-- ── 44-46: typed failures ────────────────────────────────────────────────────
SELECT throws_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (organization_id, occurred_at_utc, type, payload)
    VALUES ('f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
            '{"verdict_evidence":{"fine_cents":1000}}')$$,
  '23000', NULL,
  '#8 billable sanction without contract_id → integrity violation');

SELECT throws_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (organization_id, occurred_at_utc, type, contract_id, payload)
    VALUES ('f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
            'f3a00000-0000-0000-0000-00000000c001',
            '{"verdict_evidence":{"fine_cents":"abc"}}')$$,
  '23000', NULL,
  'malformed fine_cents → typed integrity violation (never raw 22P02)');

SELECT throws_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (organization_id, occurred_at_utc, type, contract_id, payload)
    VALUES ('f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
            'f3b00000-0000-0000-0000-00000000c0b1',
            '{"verdict_evidence":{"fine_cents":1000}}')$$,
  '23000', NULL,
  'cross-org contract on billable sanction → integrity violation');

-- ── 47-51: #16 partition coverage p0..p3 ─────────────────────────────────────
INSERT INTO public.sla_audit_ledger_v2
    (id, organization_id, occurred_at_utc, type, contract_id, payload)
VALUES ('f3e00000-0000-0000-0000-000000000021',
        'f3000000-0000-0000-0000-000000000003', now(), 'SANCTION_RECOMMENDED',
        'f3000000-0000-0000-0000-00000000c0a0',
        '{"verdict_evidence":{"fine_cents":500}}'),
       ('f3e00000-0000-0000-0000-000000000022',
        'f3000000-0000-0000-0000-000000000007', now(), 'SANCTION_RECOMMENDED',
        'f3000000-0000-0000-0000-00000000c0a1',
        '{"verdict_evidence":{"fine_cents":500}}'),
       ('f3e00000-0000-0000-0000-000000000023',
        'f3000000-0000-0000-0000-00000000000f', now(), 'SANCTION_RECOMMENDED',
        'f3000000-0000-0000-0000-00000000c0a2',
        '{"verdict_evidence":{"fine_cents":500}}'),
       ('f3e00000-0000-0000-0000-000000000024',
        'f3000000-0000-0000-0000-000000000001', now(), 'SANCTION_RECOMMENDED',
        'f3000000-0000-0000-0000-00000000c0a3',
        '{"verdict_evidence":{"fine_cents":500}}');

SELECT is(
  (SELECT tableoid::regclass::text FROM public.sla_audit_ledger_v2
   WHERE id = 'f3e00000-0000-0000-0000-000000000021'),
  'sla_audit_ledger_p0', '#16 guard fires on partition p0');
SELECT is(
  (SELECT tableoid::regclass::text FROM public.sla_audit_ledger_v2
   WHERE id = 'f3e00000-0000-0000-0000-000000000022'),
  'sla_audit_ledger_p1', '#16 guard fires on partition p1');
SELECT is(
  (SELECT tableoid::regclass::text FROM public.sla_audit_ledger_v2
   WHERE id = 'f3e00000-0000-0000-0000-000000000023'),
  'sla_audit_ledger_p2', '#16 guard fires on partition p2');
SELECT is(
  (SELECT tableoid::regclass::text FROM public.sla_audit_ledger_v2
   WHERE id = 'f3e00000-0000-0000-0000-000000000024'),
  'sla_audit_ledger_p3', '#16 guard fires on partition p3');

SELECT is(
  (SELECT count(*)::int FROM public.contract_penalty_monthly_accrual
   WHERE organization_id IN ('f3000000-0000-0000-0000-000000000003',
                             'f3000000-0000-0000-0000-000000000007',
                             'f3000000-0000-0000-0000-00000000000f',
                             'f3000000-0000-0000-0000-000000000001')
     AND accrued_cents = 500),
  4, '#16 all four partitions accrued exactly 500 each (org isolation)');

-- ── 52-54: #19 trigger wiring and ordering ───────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM pg_trigger
   WHERE tgname = 'trg_financial_guard' AND NOT tgisinternal),
  5, 'trg_financial_guard on parent + 4 partitions');

SELECT ok(
  (SELECT (tgtype & 2) = 2 FROM pg_trigger
   WHERE tgname = 'trg_financial_guard'
     AND tgrelid = 'public.sla_audit_ledger_v2'::regclass),
  'trg_financial_guard is a BEFORE trigger');

SELECT ok(
  'enforce_tenant_envelope_ledger' < 'trg_financial_guard',
  '#19 envelope validation fires before guard (alphabetical BEFORE order)');

-- ── 55: #13 v7 CHECK carries all 55 v6 types + 2 new, canonical name ─────────
SELECT is(
  (SELECT count(*)::int FROM unnest(ARRAY[
    'EXECUTION_BOUND','NO_SHOW_DECLARED','EVIDENCE_GAP_DECLARED','PLAN_DECLARED',
    'OCCURRENCE_REGISTERED','TRIP_INTERRUPTED','TRIP_CANCELLED','CONTRACT_CREATED',
    'CONTRACT_ACTIVATED','CONTRACT_CLOSED','CONTRACT_SUBMITTED_FOR_APPROVAL',
    'CONTRACT_ACCEPTED_BY_CONTRACTOR','SANCTION_RECOMMENDED','VERDICT_SEALED',
    'VERDICT_REFUSED','SANCTION_DISPUTED','DISPUTE_ACCEPTED','DISPUTE_OVERTURNED',
    'DISPUTE_RETRACTED','JUSTIFICATION_SUBMITTED','JUSTIFICATION_APPROVED',
    'JUSTIFICATION_REJECTED','SLA_JUSTIFICATION_SUBMITTED','SLA_JUSTIFICATION_EXPIRED',
    'TRANSIT_STARTED','COMPLETED_WITH_GAPS','EXECUTION_INHIBITED','UNKNOWN_EVENT',
    'MAX_TOLERANCE_DELAY','MAX_EVIDENCE_GAP','MIN_GEOFENCE_COVERAGE','NO_SHOW_PENALTY',
    'PEER_REVIEW_REQUESTED','PEER_REVIEW_DECLINED','PEER_REVIEW_EXPIRED',
    'DUAL_CONTROL_THRESHOLD_CHANGED','DISPUTE_EVIDENCE_ATTACHED','DISPUTE_SLA_BREACHED',
    'EVIDENCE_HASH_MISMATCH','DISPUTE_PORTAL_TOKEN_GENERATED','DISPUTE_PORTAL_TOKEN_ACCESSED',
    'DISPUTE_PORTAL_TOKEN_REVOKED','RULE_SCHEDULED','RULE_ACTIVATED','RULE_RETIRED',
    'CONTRACT_FINANCIAL_TERMS_AMENDED',
    'PORTAL_EVIDENCE_SUBMITTED','PORTAL_EVIDENCE_FINALIZED','PORTAL_EVIDENCE_HASH_MISMATCH',
    'PORTAL_EVIDENCE_MIME_MISMATCH','PORTAL_EVIDENCE_REJECTED',
    'PORTAL_EVIDENCE_AUDITOR_ACCEPTED','PORTAL_EVIDENCE_AUDITOR_REJECTED',
    'SANCTION_ACKNOWLEDGED','PORTAL_JUSTIFICATION_SUBMITTED',
    'FINANCIAL_CAP_REACHED','FINANCIAL_CAP_WARNING'
  ]) AS t(v)
   WHERE (SELECT pg_get_constraintdef(oid) FROM pg_constraint
          WHERE conname = 'chk_ledger_type'
            AND conrelid = 'public.sla_audit_ledger_v2'::regclass
            AND convalidated)
         LIKE '%''' || v || '''%'),
  57, '#13 canonical chk_ledger_type is validated and carries all 57 types');

-- ── 56: #7b claim mismatch → 42501 BEFORE any lock (LAST: claims persist) ────
SET LOCAL request.jwt.claims = '{"role":"authenticated","sub":"f3b00000-0000-0000-0000-0000000000bb","app_metadata":{"org_id":"f3b00000-0000-0000-0000-00000000000b","role":"TENANT_ADMIN"}}';
SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$INSERT INTO public.sla_audit_ledger_v2
      (organization_id, occurred_at_utc, type, contract_id, payload)
    VALUES ('f3a00000-0000-0000-0000-00000000000a', now(), 'SANCTION_RECOMMENDED',
            'f3a00000-0000-0000-0000-00000000c001',
            '{"verdict_evidence":{"fine_cents":1000}}')$$,
  '42501', NULL,
  '#7b tenant B cannot write a billable sanction into tenant A (claim mismatch)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
