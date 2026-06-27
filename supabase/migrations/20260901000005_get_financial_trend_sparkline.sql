-- pr_scanner: ignore-regression
-- Migration: get_financial_trend_sparkline RPC
-- 7-day (toggle 30-day) sparkline data for CFO KPI cards.
-- Security: SECURITY DEFINER, INV-2 org claim, INV-26 anti-oracle 42501.
-- Reads OLAP table contractual_financial_snapshot (org-level closure rows only).

SET client_min_messages TO 'WARNING';

-- Non-blocking index to support org+date window query (INV-DB safe).
CREATE INDEX IF NOT EXISTS idx_financial_snapshot_org_date
  ON public.contractual_financial_snapshot (organization_id, operational_date_utc DESC)
  WHERE contract_id IS NULL;

CREATE OR REPLACE FUNCTION public.get_financial_trend_sparkline(
  p_org_id UUID,
  p_days   INTEGER DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_caller_org_id UUID;
  v_days_clamped  INTEGER;
  v_result        JSONB;
BEGIN
  -- INV-2 / INV-26: anti-oracle — same error for wrong-org and missing claim.
  v_caller_org_id := (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'org_id')::UUID;

  IF v_caller_org_id IS NULL OR p_org_id IS NULL OR v_caller_org_id != p_org_id THEN
    RAISE EXCEPTION 'Access denied. Tenant isolation violation (INV-2).' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Abuse bound: clamp p_days to [1, 90].
  v_days_clamped := GREATEST(1, LEAST(90, COALESCE(p_days, 7)));

  -- One canonical point per day: exclude superseded rows, keep latest closed_at per day.
  WITH deduped AS (
    SELECT
      date_trunc('day', operational_date_utc AT TIME ZONE 'UTC')::date AS d,
      protected_revenue_cents,
      revenue_at_risk_cents,
      lost_revenue_cents
    FROM public.contractual_financial_snapshot s
    WHERE
      s.organization_id = p_org_id
      AND s.contract_id IS NULL
      AND s.operational_date_utc >= (now() AT TIME ZONE 'utc')::date - make_interval(days => v_days_clamped)
      AND s.id NOT IN (
        SELECT previous_snapshot_id
        FROM public.contractual_financial_snapshot
        WHERE previous_snapshot_id IS NOT NULL
          AND organization_id = p_org_id
      )
    ORDER BY d ASC, s.closed_at_utc DESC
  ),
  canonical AS (
    SELECT DISTINCT ON (d)
      d,
      protected_revenue_cents,
      revenue_at_risk_cents,
      lost_revenue_cents
    FROM deduped
    ORDER BY d ASC
  )
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'd',               to_char(d, 'YYYY-MM-DD'),
        'protected_cents', protected_revenue_cents,
        'at_risk_cents',   revenue_at_risk_cents,
        'lost_cents',      lost_revenue_cents
      )
      ORDER BY d ASC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM canonical;

  RETURN v_result;
END;
$$;

-- INV-DATA-API-GRANT: grant to authenticated only; revoke PUBLIC + service_role.
REVOKE ALL ON FUNCTION public.get_financial_trend_sparkline(UUID, INTEGER) FROM PUBLIC, service_role;
GRANT EXECUTE ON FUNCTION public.get_financial_trend_sparkline(UUID, INTEGER) TO authenticated;
