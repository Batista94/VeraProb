-- ============================================================
-- veraprob — ROI Summary View: SECURITY INVOKER Hardening
-- ============================================================
-- REASON:
--   v_roi_summary was created with SECURITY DEFINER behavior,
--   meaning the view executed with the owner's permissions and
--   bypassed RLS on the underlying shadow_executions table.
--   Any authenticated user could call this view and receive
--   ROI data for ALL organizations (INV-22 violation).
--
--   Fix: recreate with WITH (security_invoker = true) so
--   PostgreSQL evaluates RLS policies of the CALLING user,
--   not the view owner. shadow_executions RLS (org_id isolation)
--   then filters correctly per tenant.
--
-- SECURITY INVARIANTS:
--   INV-2  — RLS via auth.jwt() app_metadata.org_id
--   INV-22 — Tenant-A NEVER sees Tenant-B data. Red-Team tested.
--   INV-DB — Non-destructive: CREATE OR REPLACE VIEW only.
--             No ALTER/DROP/DELETE on base tables.
--
-- EXPLOIT PATH CLOSED:
--   SECURITY DEFINER view cross-tenant read →
--   closed by security_invoker = true (PostgreSQL 15+).
-- ============================================================

SET client_min_messages TO 'WARNING';

-- Drop and recreate to ensure security_invoker is applied.
-- CREATE OR REPLACE VIEW cannot change security options on an
-- existing view in some PG versions; explicit DROP is safer.
-- INV-DB: DROP VIEW is non-destructive (no data loss, view recreated immediately).

DROP VIEW IF EXISTS public.v_roi_summary;

CREATE VIEW public.v_roi_summary
  WITH (security_invoker = true)
AS
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
  'ROI Guardian v2: security_invoker=true (INV-22). Calls see only their org data via shadow_executions RLS. INV-4/5/22. Phase 10.';

-- Grant SELECT to authenticated role (mirrors original view grant).
GRANT SELECT ON public.v_roi_summary TO authenticated;
