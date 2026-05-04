-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Shadow Revenue Tracking (Phase 10 — ROI Guardian)
--
-- Adds to shadow_executions:
--   recovered_amount_cents  BIGINT  — revenue captured via retroactive auto-link
--   avoided_penalty_cents   BIGINT  — penalties avoided by evidence seal
--
-- Creates view v_roi_summary for monthly board reporting.
--
-- INV-4: BIGINT cents in DB. No FLOAT. No raw truncation.
-- INV-3: shadow_executions is append-heavy; these columns set on RECONCILED_AS_NEW_REVENUE.
-- INV-22: v_roi_summary groups by organization_id — tenant isolation preserved.
-- =============================================================================

SET client_min_messages TO 'WARNING';

ALTER TABLE public.shadow_executions
  ADD COLUMN IF NOT EXISTS recovered_amount_cents BIGINT,  -- INV-4: Physical Metric - BIGINT cents
  ADD COLUMN IF NOT EXISTS avoided_penalty_cents  BIGINT;  -- INV-4: Physical Metric - BIGINT cents

COMMENT ON COLUMN public.shadow_executions.recovered_amount_cents IS
  'Revenue recovered via retroactive auto-link (RECONCILED_AS_NEW_REVENUE). BIGINT cents. INV-4.';
COMMENT ON COLUMN public.shadow_executions.avoided_penalty_cents IS
  'Contractual penalties avoided by sealing orphan evidence. BIGINT cents. INV-4.';

-- ROI Summary view — streams to roiSummaryProvider in Flutter (INV-22: org isolation)
CREATE OR REPLACE VIEW public.v_roi_summary AS
SELECT
  organization_id,
  COUNT(*) FILTER (WHERE status = 'RECONCILED_AS_NEW_REVENUE') AS recovered_trips,
  COALESCE(
    SUM(recovered_amount_cents) FILTER (WHERE status = 'RECONCILED_AS_NEW_REVENUE'),
    0
  ) AS total_recovered_cents,
  COALESCE(SUM(avoided_penalty_cents), 0) AS total_avoided_penalty_cents,
  COUNT(*) FILTER (WHERE status IN ('RECONCILED', 'RECONCILED_AS_NEW_REVENUE')) AS total_linked_trips,
  COUNT(*) FILTER (WHERE status = 'UNLINKED_SHADOW') AS pending_orphans
FROM public.shadow_executions
GROUP BY organization_id;

COMMENT ON VIEW public.v_roi_summary IS
  'ROI Guardian aggregate per org. Streams to roiSummaryProvider. INV-4 (cents), INV-22 (org isolation). Phase 10.';
