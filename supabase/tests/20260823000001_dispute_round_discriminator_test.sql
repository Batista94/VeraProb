-- Structural coverage for 20260823000001_dispute_round_discriminator.sql
-- Verifies: dispute_round column (NOT NULL, default 0), the legacy resolution
-- indexes are dropped, and the cycle-scoped unique indexes exist (unique,
-- partial, 3-key). Local pgTAP lacks the schema-qualified col_is_nullable
-- overload → assert nullability via information_schema + ok() (see memory).
BEGIN;
SELECT plan(11);

-- ── Column present ───────────────────────────────────────────────────────────
SELECT has_column('public', 'sanction_review_queue', 'dispute_round',
  'sanction_review_queue.dispute_round exists');

SELECT col_type_is('public', 'sanction_review_queue', 'dispute_round', 'integer',
  'dispute_round is integer');

SELECT ok(
  (SELECT is_nullable = 'NO' FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
      AND column_name = 'dispute_round'),
  'dispute_round is NOT NULL');

SELECT ok(
  (SELECT column_default LIKE '0%' FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'sanction_review_queue'
      AND column_name = 'dispute_round'),
  'dispute_round defaults to 0');

-- ── Legacy indexes dropped (one resolution per entry FOREVER → gone) ─────────
SELECT ok(
  NOT EXISTS (SELECT 1 FROM pg_indexes
              WHERE schemaname = 'public' AND indexname = 'uq_ledger_resolution_p0'),
  'legacy uq_ledger_resolution_p0 dropped');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM pg_indexes
              WHERE schemaname = 'public' AND indexname = 'uq_ledger_resolution_p3'),
  'legacy uq_ledger_resolution_p3 dropped');

-- ── Cycle-scoped indexes present on every child partition ───────────────────
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes
          WHERE schemaname = 'public' AND indexname = 'uq_ledger_resolution_cycle_p0'),
  'uq_ledger_resolution_cycle_p0 exists');
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes
          WHERE schemaname = 'public' AND indexname = 'uq_ledger_resolution_cycle_p3'),
  'uq_ledger_resolution_cycle_p3 exists');

-- ── New index is UNIQUE, PARTIAL, and keyed on dispute_round ────────────────
SELECT ok(
  (SELECT indisunique FROM pg_index i
     JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_ledger_resolution_cycle_p0'),
  'cycle index is UNIQUE');
SELECT ok(
  (SELECT indpred IS NOT NULL FROM pg_index i
     JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_ledger_resolution_cycle_p0'),
  'cycle index is PARTIAL (type predicate)');
SELECT ok(
  (SELECT pg_get_indexdef(i.indexrelid) LIKE '%dispute_round%'
     FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'uq_ledger_resolution_cycle_p0'),
  'cycle index keys on payload->>dispute_round');

SELECT * FROM finish();
ROLLBACK;
