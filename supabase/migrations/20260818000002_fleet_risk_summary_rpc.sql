-- =============================================================================
-- Migration: `get_fleet_risk_summary` RPC — Sprint C (Read Models) — Phase 10.6
--
-- Purpose:   Server-side SLA breach-risk ranking for the fleet Risk Thermometer.
--            Replaces a Dart loop that pulled every `planned` window into memory
--            and ran `SlaBreachRiskCalculator` per row (O(n) over the wire). This
--            RPC computes risk_bps in SQL — byte-identical to the Dart calculator
--            (INV-15) — and returns only the worst N windows.
--
-- Source:    `execution_states` (the live execution-window projection), filtered
--            to active states `('planned','inTransit')`. Backed by the existing
--            partial index `idx_execution_states_fsm_active_expired
--            (organization_id, window_end_utc) WHERE status IN ('planned',
--            'inTransit')` (INV-12) — no new index needed.
--
-- Risk math (mirrors lib/domain/sla_audit/sla_breach_risk_calculator.dart):
--   buffer_secs = (total_secs * 1500 + 5000) / 10000   -- 15% safety buffer,
--                                                          round half away from 0
--   risk_window_start = window_end_utc - buffer_secs
--   elapsed_secs = NOW() - risk_window_start
--   risk_bps = buffer>0 ? (elapsed * 10000) / buffer    -- integer div, trunc→0
--                       : (elapsed >= 0 ? 10000 : -10000)
--   (riskBps: <0 safe · 0 buffer-entry · 8500 critical/pulse · 10000 deadline)
--
-- INV-1:  organization_id filter on the source; RPC scoped to caller org.
-- INV-5:  integer basis-point arithmetic only — no float drift.
-- INV-6:  all timestamps TIMESTAMPTZ; NOW() is UTC server clock.
-- INV-15: deterministic — identical to the Dart calculator for the same inputs.
-- INV-26: anti-oracle — JWT org mismatch returns 0 rows, never an error.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
--          (plan `convoque-o-conselho-de-linear-diffie`, Sprint C).
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.get_fleet_risk_summary(
  p_organization_id UUID,
  p_limit           INT DEFAULT 10
)
RETURNS TABLE (
  set_id                  TEXT,
  contract_id             TEXT,
  window_start_utc        TIMESTAMPTZ,
  window_end_utc          TIMESTAMPTZ,
  risk_bps                BIGINT,
  contractual_value_cents BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
STABLE
AS $$
DECLARE
  v_jwt_org TEXT;
BEGIN
  -- INV-26: anti-oracle — auth shortfall yields 0 rows, never an error.
  v_jwt_org := auth.jwt() -> 'app_metadata' ->> 'org_id';
  IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH active AS (
    SELECT
      es.set_id,
      es.contract_id,
      es.window_start_utc,
      es.window_end_utc,
      es.contractual_value_cents,
      EXTRACT(EPOCH FROM (es.window_end_utc - es.window_start_utc))::BIGINT AS total_secs
    FROM public.execution_states es
    WHERE es.organization_id = p_organization_id
      AND es.status IN ('planned', 'inTransit')
  ),
  buffered AS (
    -- Skip degenerate windows (end <= start): undefined risk, excluded.
    SELECT
      a.*,
      (a.total_secs * 1500 + 5000) / 10000 AS buffer_secs
    FROM active a
    WHERE a.total_secs > 0
  ),
  scored AS (
    SELECT
      b.set_id,
      b.contract_id,
      b.window_start_utc,
      b.window_end_utc,
      b.contractual_value_cents,
      b.buffer_secs,
      EXTRACT(EPOCH FROM (
        NOW() - (b.window_end_utc - make_interval(secs => b.buffer_secs::double precision))
      ))::BIGINT AS elapsed_secs
    FROM buffered b
  )
  SELECT
    s.set_id,
    s.contract_id,
    s.window_start_utc,
    s.window_end_utc,
    CASE
      WHEN s.buffer_secs > 0 THEN (s.elapsed_secs * 10000) / s.buffer_secs
      WHEN s.elapsed_secs >= 0 THEN 10000
      ELSE -10000
    END AS risk_bps,
    s.contractual_value_cents
  FROM scored s
  ORDER BY risk_bps DESC, s.window_end_utc ASC
  LIMIT GREATEST(p_limit, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.get_fleet_risk_summary(UUID, INT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_fleet_risk_summary(UUID, INT)
  TO authenticated, service_role;

RESET client_min_messages;
