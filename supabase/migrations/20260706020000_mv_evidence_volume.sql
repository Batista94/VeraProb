-- =============================================================================
-- Migration: Materialized View `mv_evidence_volume`
--
-- Aggregates per-organization evidence upload counts from both forensic sources:
--   - justification_evidence_uploads (contractor SLA justifications)
--   - telegram_evidence_uploads      (driver chat-bound photo/audio evidence)
--
-- Consumers:
--   - Edge Function `super-admin-proxy` (action: get_evidence_volume)
--   - Riverpod provider `evidenceVolumeView` (SuperAdmin TenantDetail screen)
--
-- Why a materialized view (and not a regular VIEW or RPC):
--   A live `COUNT(*)` over both append-only tables grows O(n) per request and
--   would re-scan millions of rows on every SuperAdmin panel load. The MV is
--   refreshed asynchronously, keeping the read path O(1) for the UI.
--
-- INV-1:  organization_id is the partition key on the MV. Edge filters by
--         tenant on every read (`.eq("organization_id", orgId)`); MV has no
--         RLS itself (MVs do not inherit RLS), so access is gated by being
--         readable only from `service_role`.
-- INV-6:  uploaded_at_utc is TIMESTAMPTZ on both sources; the monthly filter
--         uses `date_trunc('month', NOW() AT TIME ZONE 'UTC')`.
-- INV-7:  counts typed as BIGINT (forensic-safe — large orgs may exceed INT4).
-- INV-15: deterministic — same source rows always produce same MV state after
--         REFRESH. UNION ALL preserves provenance per source table.
-- INV-23: pg_cron refresh is guarded by `IF EXISTS pg_namespace 'cron'` so the
--         migration succeeds in local dev (no pg_cron there). Dev tests will
--         see the initial REFRESH state only — acceptable for test fixtures
--         that don't write evidence between refreshes.
-- INV-DB: zero-downtime — CREATE MATERIALIZED VIEW takes an AccessExclusiveLock
--         only on the new MV's catalog entry (a brand-new object), not on the
--         source tables. The initial REFRESH does a sequential scan but holds
--         only AccessShareLock on the sources (concurrent INSERTs unaffected).
--         A UNIQUE INDEX on `organization_id` enables `REFRESH CONCURRENTLY`,
--         which the pg_cron job uses to avoid blocking SELECTs.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Materialized View ─────────────────────────────────────────────────────
-- Drop & recreate is safe here because this is the first time the MV is being
-- introduced. The `IF EXISTS` makes the migration idempotent.

DROP MATERIALIZED VIEW IF EXISTS public.mv_evidence_volume; -- INV-DB: zero-downtime-verified

CREATE MATERIALIZED VIEW public.mv_evidence_volume AS
WITH all_evidence AS (
  SELECT
    organization_id,
    uploaded_at_utc
  FROM public.justification_evidence_uploads

  UNION ALL

  SELECT
    organization_id,
    uploaded_at_utc
  FROM public.telegram_evidence_uploads
)
SELECT
  organization_id,
  COUNT(*)::BIGINT AS total_historical,
  COUNT(*) FILTER (
    WHERE uploaded_at_utc >= date_trunc('month', NOW() AT TIME ZONE 'UTC')
  )::BIGINT AS total_monthly
FROM all_evidence
GROUP BY organization_id
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW public.mv_evidence_volume IS
  'Per-organization evidence upload counts (historical + current month). '
  'Refreshed every 5 minutes by pg_cron job `refresh-mv-evidence-volume` on Supabase Cloud. '
  'Sources: justification_evidence_uploads + telegram_evidence_uploads (UNION ALL). '
  'INV-1: filter by organization_id on read. INV-7: counts are BIGINT.';

-- ── 2. Unique index — required for REFRESH MATERIALIZED VIEW CONCURRENTLY ───
-- Without a unique index, only `REFRESH MATERIALIZED VIEW` (blocking) is
-- allowed. CONCURRENTLY needs a UNIQUE row identifier — organization_id is
-- naturally unique here because of the outer GROUP BY.

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_evidence_volume_org
  ON public.mv_evidence_volume (organization_id);

-- ── 3. Initial population ────────────────────────────────────────────────────
-- Non-CONCURRENTLY is correct on the first refresh (CONCURRENTLY requires the
-- MV to be already populated). Blocks reads briefly, but the MV is brand-new
-- so no consumer is querying it yet.

REFRESH MATERIALIZED VIEW public.mv_evidence_volume;

-- ── 4. Access control ────────────────────────────────────────────────────────
-- MVs do not inherit RLS. The Edge Function uses the service-role client which
-- bypasses RLS, so we lock the MV down to service_role only. anon/authenticated
-- must never reach this MV — they would see cross-tenant counts (INV-1 / INV-22).

REVOKE ALL ON public.mv_evidence_volume FROM PUBLIC;
REVOKE ALL ON public.mv_evidence_volume FROM anon;
REVOKE ALL ON public.mv_evidence_volume FROM authenticated;
GRANT SELECT ON public.mv_evidence_volume TO service_role;

-- ── 5. Scheduled refresh (Supabase Cloud only) ───────────────────────────────
-- Local dev (`supabase start`) does not install pg_cron — the DO block exits
-- silently. On Cloud, the MV is refreshed every 5 minutes CONCURRENTLY so
-- SELECTs from super-admin-proxy never block.
--
-- Latency budget: SuperAdmin sees evidence volume with up to 5 min lag.
-- Acceptable because the figure is informational, not a financial trigger.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    -- Unschedule any prior job with same name (idempotent re-runs).
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'refresh-mv-evidence-volume';

    PERFORM cron.schedule(
      'refresh-mv-evidence-volume',
      '*/5 * * * *',
      $cron$ REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_evidence_volume; $cron$
    );
  END IF;
END;
$$;
