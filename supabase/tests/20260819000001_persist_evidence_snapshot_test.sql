BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- =============================================================================
-- pgTAP: _persist_evidence_snapshot helper + verify_forensic_evidence_by_queue
-- Migration: 20260819000001_persist_evidence_snapshot_helper.sql
--            20260819000002_forensic_evidence_by_queue.sql
-- Focus: ADD COLUMN queue_entry_id, helper extraction, approve_sanction seals
--   snapshot bound to the queue entry, verify_by_queue returns authentic.
-- =============================================================================

-- ── Seeds ─────────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  'a1a1a1a1-0000-0000-0000-000000000001', 'Org Snapshot BUG1', 'Org Snapshot BUG1 SA',
  'a1a10000000001', 'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 5000,
  300, 15, 'bug1@test.com', 'EXT_BUG1', 'LOGISTICS', ARRAY['bug1.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.contract_rule_sets (id, organization_id, contract_id)
VALUES (
  'a1a1a1a1-0000-0000-0000-000000000003',
  'a1a1a1a1-0000-0000-0000-000000000001',
  'a1a1a1a1-0000-0000-0000-000000000002'
) ON CONFLICT DO NOTHING;

INSERT INTO public.contract_rule_versions
  (id, rule_set_id, rule_type, rule_config, rule_version, evaluation_order,
   active_from_utc, active_to_utc, created_at_utc)
VALUES (
  'a1a1a1a1-0000-0000-0000-000000000004',
  'a1a1a1a1-0000-0000-0000-000000000003',
  'MAX_TOLERANCE_DELAY', '{"threshold_minutes": 30}'::jsonb, 1, 0,
  '2026-01-01T00:00:00Z', NULL, '2026-01-01T00:00:00Z'
) ON CONFLICT DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence,
   status, vehicle_plate)
VALUES (
  'a1a1a1a1-0000-0000-0000-000000000005',
  'a1a1a1a1-0000-0000-0000-000000000001',
  'a1a1a1a1-0000-0000-0000-0000000000f1',
  'set-bug1',
  'a1a1a1a1-0000-0000-0000-000000000002',
  '{"fine_cents": 5000}'::jsonb,
  'pending',
  'BUG1-001'
) ON CONFLICT (id) DO NOTHING;

-- T1: queue_entry_id column exists on forensic_evidence_snapshots.
SELECT has_column(
  'public', 'forensic_evidence_snapshots', 'queue_entry_id',
  'T1: forensic_evidence_snapshots has queue_entry_id column'
);

-- T2: _persist_evidence_snapshot helper exists.
SELECT has_function(
  'public', '_persist_evidence_snapshot',
  ARRAY['uuid','uuid','uuid','uuid','text','text','integer',
        'timestamp with time zone','uuid','text'],
  'T2: _persist_evidence_snapshot helper exists with 10-arg signature'
);

-- T3: verify_forensic_evidence_by_queue exists.
SELECT has_function(
  'public', 'verify_forensic_evidence_by_queue',
  ARRAY['uuid', 'uuid'],
  'T3: verify_forensic_evidence_by_queue exists (2-arg signature)'
);

-- T4: verify_forensic_evidence_by_queue is SECURITY INVOKER (RLS-scoped, INV-26).
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'verify_forensic_evidence_by_queue'),
  false,
  'T4: verify_forensic_evidence_by_queue is SECURITY INVOKER'
);

-- T5: authenticated may EXECUTE verify_forensic_evidence_by_queue.
SELECT ok(
  has_function_privilege('authenticated',
    'public.verify_forensic_evidence_by_queue(uuid, uuid)', 'EXECUTE'),
  'T5: authenticated may EXECUTE verify_forensic_evidence_by_queue'
);

-- T6: approve_sanction seals a snapshot for a pending queue entry.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"a1a1a1a1-0000-0000-0000-000000000006","organization_id":"a1a1a1a1-0000-0000-0000-000000000001","app_metadata":{"org_id":"a1a1a1a1-0000-0000-0000-000000000001","role":"AUDITOR"}}';

SELECT lives_ok(
  $$ SELECT public.approve_sanction(
       'a1a1a1a1-0000-0000-0000-000000000001',
       'a1a1a1a1-0000-0000-0000-000000000005',
       'a1a1a1a1-0000-0000-0000-000000000006',
       'auditor@bug1.com',
       '2026-08-19T10:00:00Z'
     ) $$,
  'T6: approve_sanction seals snapshot for applied queue entry'
);

RESET ROLE;
RESET request.jwt.claims;

-- T7: snapshot has queue_entry_id populated with the queue entry id.
SELECT is(
  (SELECT queue_entry_id FROM public.forensic_evidence_snapshots
    WHERE organization_id = 'a1a1a1a1-0000-0000-0000-000000000001'
      AND queue_entry_id = 'a1a1a1a1-0000-0000-0000-000000000005'),
  'a1a1a1a1-0000-0000-0000-000000000005'::uuid,
  'T7: snapshot.queue_entry_id bound to the queue entry (INV-21)'
);

-- T8: verify_forensic_evidence_by_queue returns authentic for the sealed snapshot.
SELECT is(
  (SELECT public.verify_forensic_evidence_by_queue(
     'a1a1a1a1-0000-0000-0000-000000000001',
     'a1a1a1a1-0000-0000-0000-000000000005'
   ) ->> 'status'),
  'authentic',
  'T8: verify_forensic_evidence_by_queue returns authentic for sealed queue entry'
);

-- T9: unknown queue_entry_id raises P0002 (404-parity, INV-26).
SELECT throws_ok(
  $$ SELECT public.verify_forensic_evidence_by_queue(
       'a1a1a1a1-0000-0000-0000-000000000001',
       gen_random_uuid()
     ) $$,
  'P0002', NULL,
  'T9: verify_forensic_evidence_by_queue raises P0002 for unknown queue entry'
);

SELECT * FROM finish();
ROLLBACK;
