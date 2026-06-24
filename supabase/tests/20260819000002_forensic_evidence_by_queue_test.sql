BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- =============================================================================
-- pgTAP: verify_forensic_evidence_by_queue RPC
-- Migration: 20260819000002_forensic_evidence_by_queue.sql
-- =============================================================================

-- T1: verify_forensic_evidence_by_queue exists.
SELECT has_function(
  'public', 'verify_forensic_evidence_by_queue',
  ARRAY['uuid', 'uuid'],
  'T1: verify_forensic_evidence_by_queue exists (2-arg signature)'
);

-- T2: verify_forensic_evidence_by_queue is SECURITY INVOKER (RLS-scoped, INV-26).
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'verify_forensic_evidence_by_queue'),
  false,
  'T2: verify_forensic_evidence_by_queue is SECURITY INVOKER'
);

-- T3: unknown queue_entry_id raises P0002 (404-parity, INV-26).
SELECT throws_ok(
  $$ SELECT public.verify_forensic_evidence_by_queue(
       'b2b2b2b2-0000-0000-0000-000000000001',
       'ffffffff-ffff-ffff-ffff-ffffffffffff'
     ) $$,
  'P0002', NULL,
  'T3: verify_forensic_evidence_by_queue raises P0002 for unknown queue entry'
);

SELECT * FROM finish();
ROLLBACK;
