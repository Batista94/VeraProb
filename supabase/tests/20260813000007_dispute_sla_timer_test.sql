BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ── Seeds (as postgres: bypasses RLS for fixture setup) ──────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000d2c20', 'Org SLA', 'Org SLA SA', '00000000000d40',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'sla@test.com', 'EXT_SLA', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Org-level SLA override = 7 (column defaults to 5).
UPDATE public.organizations SET dispute_resolution_sla_days = 7
 WHERE id = '00000000-0000-0000-0000-0000000d2c20';

-- Contract with an explicit override (10) and one with NULL (falls back to org).
INSERT INTO public.contracts
  (id, organization_id, name, contractor_name, valid_from_utc, valid_until_utc,
   dispute_resolution_sla_days)
VALUES
  ('11111111-1111-1111-1111-111111111110', '00000000-0000-0000-0000-0000000d2c20',
   'C-Override', 'K', now(), now() + INTERVAL '1 year', 10),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000d2c20',
   'C-Null', 'K', now(), now() + INTERVAL '1 year', NULL);

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_column('public', 'organizations', 'dispute_resolution_sla_days',
  'organizations.dispute_resolution_sla_days added');
SELECT has_column('public', 'contracts', 'dispute_resolution_sla_days',
  'contracts.dispute_resolution_sla_days added (override)');
SELECT has_column('public', 'sanction_review_queue', 'disputed_at',
  'sanction_review_queue.disputed_at added');
SELECT has_column('public', 'sanction_review_queue', 'disputed_by',
  'sanction_review_queue.disputed_by added');
SELECT has_column('public', 'sanction_review_queue', 'resolution_due_at',
  'sanction_review_queue.resolution_due_at added');

-- ── SLA-days resolution: contract → org → 5 ──────────────────────────────────
SELECT is(
  public._resolve_dispute_sla_days('00000000-0000-0000-0000-0000000d2c20', 'not-a-uuid'),
  7, 'no contract override (non-uuid id) falls back to org value (7)');

SELECT is(
  public._resolve_dispute_sla_days(
    '00000000-0000-0000-0000-0000000d2c20', '11111111-1111-1111-1111-111111111110'),
  10, 'contract override wins over org value (10)');

SELECT is(
  public._resolve_dispute_sla_days(
    '00000000-0000-0000-0000-0000000d2c20', '11111111-1111-1111-1111-111111111111'),
  7, 'contract with NULL SLA falls back to org value (COALESCE skips NULL)');

-- ── H1: ledger type CHECK widened without a no-constraint window ──────────────
-- Canonical name is preserved across the widening (swap-then-rename-back).
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_type ty
    JOIN pg_namespace n ON n.oid = ty.typnamespace
    WHERE n.nspname = 'public' AND ty.typname = 'ledger_event_type'
  ),
  'ledger_event_type enum present (replaces chk_ledger_type)');

SELECT ok(
  (SELECT count(*)::int FROM pg_constraint
     WHERE conname = 'chk_ledger_type_v2'
       AND conrelid = 'public.sla_audit_ledger_v2'::regclass) = 0,
  'transient chk_ledger_type_v2 was renamed away (no dangling constraint)');

SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, occurred_at_utc, payload)
     VALUES ('00000000-0000-0000-0000-0000000d2c20', 'DISPUTE_SLA_BREACHED', now(),
             jsonb_build_object('queue_entry_id', '22222222-2222-2222-2222-222222222001')) $$,
  'ledger accepts DISPUTE_SLA_BREACHED');

SELECT lives_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, occurred_at_utc, payload)
     VALUES ('00000000-0000-0000-0000-0000000d2c20', 'EVIDENCE_HASH_MISMATCH', now(),
             jsonb_build_object('queue_entry_id', '22222222-2222-2222-2222-222222222002')) $$,
  'ledger accepts EVIDENCE_HASH_MISMATCH');

SELECT throws_ok(
  $$ INSERT INTO public.sla_audit_ledger_v2 (organization_id, type, occurred_at_utc)
     VALUES ('00000000-0000-0000-0000-0000000d2c20', 'TOTALLY_FAKE_TYPE', now()) $$,
  '22P02', NULL,
  'ledger rejects an unknown type (enum invalid_text_representation)');

-- ── Indexes ──────────────────────────────────────────────────────────────────
SELECT has_index('public', 'sanction_review_queue', 'idx_srq_dispute_sla',
  'idx_srq_dispute_sla breach-sweep index exists');

SELECT ok(
  (SELECT i.indisunique FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
     WHERE c.relname = 'uq_ledger_sla_breach_once'),
  'uq_ledger_sla_breach_once exists and is UNIQUE (idempotency hardening)');

-- ── Breach sweep ─────────────────────────────────────────────────────────────
-- A: overdue disputed row (must be flagged). B: future-due (must be ignored).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-0000000d2c30', '00000000-0000-0000-0000-0000000d2c20',
   gen_random_uuid(), 'SLA_SET_A', '11111111-1111-1111-1111-111111111110', '{}'::jsonb,
   'disputed', now() - INTERVAL '6 days', gen_random_uuid(), now() - INTERVAL '1 day'),
  ('00000000-0000-0000-0000-0000000d2c31', '00000000-0000-0000-0000-0000000d2c20',
   gen_random_uuid(), 'SLA_SET_B', '11111111-1111-1111-1111-111111111110', '{}'::jsonb,
   'disputed', now() - INTERVAL '1 day', gen_random_uuid(), now() + INTERVAL '5 days');

SELECT is(
  public.flag_sla_breached_disputes(), 1,
  'flag_sla_breached_disputes flags exactly the one overdue disputed row');

SELECT is(
  public.flag_sla_breached_disputes(), 0,
  'second sweep is idempotent (NOT EXISTS guard returns 0)');

SELECT is(
  (SELECT status FROM public.sanction_review_queue
     WHERE id = '00000000-0000-0000-0000-0000000d2c30'),
  'disputed',
  'sweep is signal-only: queue status stays disputed (Q3)');

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
     WHERE type = 'DISPUTE_SLA_BREACHED'
       AND payload ->> 'queue_entry_id' = '00000000-0000-0000-0000-0000000d2c31'),
  0,
  'future-due disputed row is not flagged');

-- ── Function privileges ──────────────────────────────────────────────────────
SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'public.flag_sla_breached_disputes()', 'EXECUTE'),
  'authenticated cannot EXECUTE flag_sla_breached_disputes (backend-only)');

SELECT ok(
  has_function_privilege(
    'service_role', 'public.flag_sla_breached_disputes()', 'EXECUTE'),
  'service_role may EXECUTE flag_sla_breached_disputes');

SELECT ok(
  NOT has_function_privilege(
    'authenticated', 'public._resolve_dispute_sla_days(uuid, text)', 'EXECUTE'),
  'authenticated cannot EXECUTE the internal _resolve_dispute_sla_days');

SELECT * FROM finish();
ROLLBACK;
