-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: v_roi_summary v2 — ROI Formula (Phase 10)
--
-- Joins shadow_executions aggregates with organizations.tool_cost_cents.
-- INV-4: All math in BIGINT cents/bps. No floats.
-- INV-5: ROI in basis points (10000 = 100%).
-- INV-22: Grouped by organization_id.
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE VIEW public.v_roi_summary AS
SELECT
  se.organization_id,
  COUNT(*) FILTER (WHERE se.status = 'RECONCILED_AS_NEW_REVENUE')
    AS recovered_trips,
  COALESCE(SUM(se.recovered_amount_cents)
    FILTER (WHERE se.status = 'RECONCILED_AS_NEW_REVENUE'), 0)
    AS total_recovered_cents,
  COALESCE(SUM(se.avoided_penalty_cents), 0)
    AS total_avoided_penalty_cents,
  COUNT(*) FILTER (WHERE se.status IN ('RECONCILED', 'RECONCILED_AS_NEW_REVENUE'))
    AS total_linked_trips,
  COUNT(*) FILTER (WHERE se.status = 'UNLINKED_SHADOW')
    AS pending_orphans,
  o.tool_cost_cents,
  CASE
    WHEN o.tool_cost_cents > 0 THEN
      ((COALESCE(SUM(se.recovered_amount_cents)
          FILTER (WHERE se.status = 'RECONCILED_AS_NEW_REVENUE'), 0)
        + COALESCE(SUM(se.avoided_penalty_cents), 0)
        - o.tool_cost_cents) * 10000)
      / o.tool_cost_cents
    ELSE NULL
  END AS roi_bps
FROM public.shadow_executions se
JOIN public.organizations o ON o.id = se.organization_id
GROUP BY se.organization_id, o.tool_cost_cents;

COMMENT ON VIEW public.v_roi_summary IS
  'ROI Guardian v2: includes tool_cost_cents + roi_bps. INV-4/5/22. Phase 10.';
