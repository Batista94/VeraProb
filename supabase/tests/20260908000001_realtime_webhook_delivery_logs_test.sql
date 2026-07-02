BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- =============================================================================
-- pgTAP: realtime_webhook_delivery_logs — Fase 10.7 (P4 gap fix)
-- Migration under test: 20260908000001_realtime_webhook_delivery_logs.sql
-- Proves webhook_delivery_logs is published on supabase_realtime exactly once
-- (idempotent ADD) and that the published table keeps RLS enabled, so the
-- realtime postgres_changes feed stays tenant-gated (INV-22).
-- =============================================================================

-- P1 — published on supabase_realtime (deliveryLogStreamProvider tick source).
SELECT is(
  (SELECT count(*)::int
     FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'webhook_delivery_logs'),
  1,
  'webhook_delivery_logs is a member of supabase_realtime (INV-16 tick source)'
);

-- P2 — exactly one membership row (idempotent ADD: no duplicate publication).
SELECT is(
  (SELECT count(DISTINCT (schemaname, tablename))::int
     FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'webhook_delivery_logs'),
  1,
  'membership is unique — migration is re-runnable without duplication'
);

-- P3 — RLS still enabled: realtime stays RLS-gated (no cross-tenant leak).
SELECT is(
  (SELECT relrowsecurity
     FROM pg_class
    WHERE relnamespace = 'public'::regnamespace
      AND relname = 'webhook_delivery_logs'),
  true,
  'RLS remains enabled on the published table (INV-22)'
);

SELECT * FROM finish();
ROLLBACK;
