-- =============================================================================
-- Migration: Materialized View `mv_carrier_performance` + ranking RPC
--            Sprint C (Read Models) — Phase 10.6
--
-- Purpose:   Per-(organization, contract) carrier compliance scorecard for the
--            Carrier Performance Ranking panel (CFO/dispatcher demo hook). A
--            live aggregate over `shadow_verdicts` (obligation universe) joined
--            to `sanction_review_queue` (dispute + fine exposure) would re-scan
--            both append-only tables on every panel load; the MV keeps the read
--            path O(1) and is refreshed hourly by pg_cron on Cloud.
--
-- Consumers: RPC `get_carrier_performance_ranking` → Riverpod `carrierRanking`.
--
-- Tenant gating (MVs have NO RLS): the MV is locked to `service_role`; tenant
-- access is ONLY through the SECURITY DEFINER RPC below, which gates on the JWT
-- `app_metadata.org_id` and returns 0 rows on mismatch (anti-oracle INV-26) —
-- never an error that would distinguish "no data" from "wrong tenant".
--
-- INV-1:  organization_id present on every row; RPC filters by caller org.
-- INV-5:  compliance/dispute rates are integer basis points
--         `(numerator * 10000) / GREATEST(denominator, 1)` — no float, no raw
--         truncation surprise (denominator never 0).
-- INV-6:  last_evaluated_utc is TIMESTAMPTZ (UTC).
-- INV-7:  counts are BIGINT (large carriers may exceed INT4).
-- INV-12: source index `idx_sv_carrier_rank (organization_id, contract_id)`
--         supports the MV's GROUP BY.
-- INV-15: deterministic — same source rows always produce the same MV state.
-- INV-16: one extra hourly cron job (REFRESH ~seconds); ≤2 concurrent jobs,
--         well within the 60-connection Free-Tier budget.
-- INV-DB: zero-downtime — CREATE MATERIALIZED VIEW locks only the new object;
--         the initial REFRESH holds AccessShareLock on the sources. UNIQUE INDEX
--         enables REFRESH CONCURRENTLY (non-blocking on Cloud).
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
--          (plan `convoque-o-conselho-de-linear-diffie`, Sprint C).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Source index for the GROUP BY (INV-12) ────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sv_carrier_rank
  ON public.shadow_verdicts (organization_id, contract_id);

-- ── 2. Materialized View ─────────────────────────────────────────────────────
-- DROP & recreate is safe: first introduction, IF EXISTS keeps re-runs idempotent.
DROP MATERIALIZED VIEW IF EXISTS public.mv_carrier_performance; -- INV-DB: zero-downtime-verified

CREATE MATERIALIZED VIEW public.mv_carrier_performance AS
WITH sv AS (
  -- Obligation universe: one shadow verdict per (org, set, contract).
  SELECT
    organization_id,
    contract_id,
    COUNT(*)::BIGINT                                                      AS total_obligations,
    COUNT(*) FILTER (WHERE engine_verdict = 'executed')::BIGINT          AS executed_count,
    COUNT(*) FILTER (WHERE engine_verdict = 'noShow')::BIGINT            AS no_show_count,
    COUNT(*) FILTER (WHERE engine_verdict = 'evidenceGap')::BIGINT       AS evidence_gap_count,
    COUNT(*) FILTER (WHERE divergence_type = 'false_positive')::BIGINT   AS false_positive_count,
    COUNT(*) FILTER (WHERE divergence_type = 'false_negative')::BIGINT   AS false_negative_count,
    MAX(engine_verdict_at_utc)                                           AS last_evaluated_utc
  FROM public.shadow_verdicts
  GROUP BY organization_id, contract_id
),
srq AS (
  -- Dispute pressure + financial exposure from the live verdict queue.
  SELECT
    organization_id,
    contract_id,
    COUNT(*) FILTER (WHERE status = 'disputed')::BIGINT                          AS dispute_count,
    COALESCE(SUM((verdict_evidence ->> 'fine_cents')::BIGINT), 0)::BIGINT        AS total_fine_exposure_cents
  FROM public.sanction_review_queue
  GROUP BY organization_id, contract_id
)
SELECT
  sv.organization_id,
  sv.contract_id,
  sv.total_obligations,
  sv.executed_count,
  sv.no_show_count,
  sv.evidence_gap_count,
  sv.false_positive_count,
  sv.false_negative_count,
  -- INV-5: integer bps; denominator guarded so it is never zero.
  ((sv.executed_count * 10000) / GREATEST(sv.total_obligations, 1))::INT         AS compliance_rate_bps,
  COALESCE(srq.dispute_count, 0)::BIGINT                                         AS dispute_count,
  ((COALESCE(srq.dispute_count, 0) * 10000) / GREATEST(sv.total_obligations, 1))::INT
                                                                                AS dispute_rate_bps,
  COALESCE(srq.total_fine_exposure_cents, 0)::BIGINT                             AS total_fine_exposure_cents,
  sv.last_evaluated_utc
FROM sv
LEFT JOIN srq
  ON srq.organization_id = sv.organization_id
 AND srq.contract_id     = sv.contract_id
WITH NO DATA;

COMMENT ON MATERIALIZED VIEW public.mv_carrier_performance IS
  'Per-(organization, contract) carrier compliance scorecard. Obligation counts '
  'from shadow_verdicts; dispute_count + total_fine_exposure_cents from '
  'sanction_review_queue. compliance_rate_bps = executed/total (INV-5 integer '
  'bps); dispute_rate_bps = disputes/total. Refreshed hourly by pg_cron '
  '`refresh-mv-carrier-performance` on Cloud. service_role only — tenant access '
  'via get_carrier_performance_ranking RPC (INV-22/26).';

-- ── 3. Unique index — required for REFRESH ... CONCURRENTLY ───────────────────
-- (organization_id, contract_id) is unique by the outer GROUP BY grain.
CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_carrier_performance
  ON public.mv_carrier_performance (organization_id, contract_id);

-- ── 4. Initial population ────────────────────────────────────────────────────
REFRESH MATERIALIZED VIEW public.mv_carrier_performance;

-- ── 5. Access control (MVs do not inherit RLS) ───────────────────────────────
REVOKE ALL ON public.mv_carrier_performance FROM PUBLIC;
REVOKE ALL ON public.mv_carrier_performance FROM anon;
REVOKE ALL ON public.mv_carrier_performance FROM authenticated;
GRANT SELECT ON public.mv_carrier_performance TO service_role;

-- ── 6. Tenant-scoped ranking RPC (anti-oracle) ───────────────────────────────
-- SECURITY DEFINER reads the locked-down MV; the JWT org gate returns 0 rows on
-- mismatch (INV-26) instead of raising — "wrong tenant" is indistinguishable
-- from "no contracts". Worst performers first (compliance_rate_bps ASC).
CREATE OR REPLACE FUNCTION public.get_carrier_performance_ranking(
  p_organization_id UUID,
  p_limit           INT DEFAULT 20
)
RETURNS TABLE (
  organization_id          UUID,
  contract_id              TEXT,
  total_obligations        BIGINT,
  executed_count           BIGINT,
  no_show_count            BIGINT,
  evidence_gap_count       BIGINT,
  false_positive_count     BIGINT,
  false_negative_count     BIGINT,
  compliance_rate_bps      INT,
  dispute_count            BIGINT,
  dispute_rate_bps         INT,
  total_fine_exposure_cents BIGINT,
  last_evaluated_utc       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
STABLE
AS $$
DECLARE
  v_jwt_org TEXT;
BEGIN
  -- INV-26: anti-oracle — any auth shortfall yields 0 rows, never an error.
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT
      mv.organization_id,
      mv.contract_id,
      mv.total_obligations,
      mv.executed_count,
      mv.no_show_count,
      mv.evidence_gap_count,
      mv.false_positive_count,
      mv.false_negative_count,
      mv.compliance_rate_bps,
      mv.dispute_count,
      mv.dispute_rate_bps,
      mv.total_fine_exposure_cents,
      mv.last_evaluated_utc
    FROM public.mv_carrier_performance mv
   WHERE mv.organization_id = p_organization_id
   ORDER BY mv.compliance_rate_bps ASC, mv.contract_id ASC
   LIMIT GREATEST(p_limit, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.get_carrier_performance_ranking(UUID, INT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_carrier_performance_ranking(UUID, INT)
  TO authenticated, service_role;

-- ── 7. Scheduled refresh (Supabase Cloud only) ───────────────────────────────
-- Local dev has no pg_cron — the DO block exits silently. Hourly CONCURRENTLY
-- so tenant SELECTs (via the RPC) never block. Latency budget: ranking lags up
-- to 1h, acceptable for an informational scorecard (not a financial trigger).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'refresh-mv-carrier-performance';

    PERFORM cron.schedule(
      'refresh-mv-carrier-performance',
      '0 * * * *',
      $cron$ REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_carrier_performance; $cron$
    );
  END IF;
END;
$$;

RESET client_min_messages;
