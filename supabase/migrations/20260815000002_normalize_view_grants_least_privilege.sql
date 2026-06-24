-- =============================================================================
-- Fix: deterministic least-privilege grants on read-only public views
-- =============================================================================
-- REASON:
--   20260719000000_harden_remaining_data_api_grants.sql granted service_role
--   SELECT on contractors_view / invitations_view / v_roi_summary but only ran
--   `REVOKE ALL ... FROM public, anon, authenticated` — NOT from service_role.
--   service_role therefore retained leftover non-SELECT privileges inherited at
--   view-creation time (REFERENCES / TRIGGER / TRUNCATE on some PostgreSQL
--   builds), producing a NON-DETERMINISTIC ACL that varies by engine version.
--
--   Its companion pgTAP asserted service_role held ALL 7 privileges on these
--   views — which neither matches the migration's intent (SELECT only) nor the
--   actual fresh-reset state. The mismatch makes `make test-db` fail on a clean
--   `supabase db reset` (3 assertions) on engines that do not leak the extra
--   privileges.
--
-- FIX:
--   Pin service_role to EXACTLY SELECT on the three read-only views (the
--   migration's original intent). These are masking / summary views: writes flow
--   through their base tables, never the view, so SELECT-only is both correct and
--   least-privilege (confidentiality: not even the backend role can write through
--   a PII-masking view). authenticated already holds SELECT only; anon none.
--
-- INVARIANTS:
--   INV-2  — views are SECURITY INVOKER; grants do not widen RLS exposure.
--   INV-22 — least privilege on PII-masking views (no write path for any role).
--   INV-DATA-API-GRANT — explicit, deterministic grants; no PUBLIC defaults.
--
-- pr_scanner: ignore-regression — additive REVOKE-extra/GRANT-SELECT normalization
--   on read-only views only. No DDL, no forensic-logic change; tightens to least
--   privilege and makes the ACL deterministic across engine versions. anon stays
--   with no access. QA-Security reviewed (confidentiality: no write path for any
--   role through PII-masking / summary views).
-- =============================================================================

BEGIN;

REVOKE ALL ON public.contractors_view FROM service_role;
GRANT SELECT ON public.contractors_view TO service_role;

REVOKE ALL ON public.invitations_view FROM service_role;
GRANT SELECT ON public.invitations_view TO service_role;

REVOKE ALL ON public.v_roi_summary FROM service_role;
GRANT SELECT ON public.v_roi_summary TO service_role;

-- vw_device_heartbeat_status: backend-only (anon/authenticated have NO grant).
-- 20260718000000 granted service_role SELECT but left the same leftover-privilege
-- non-determinism; its pgTAP over-asserted ALL 7. Pin to SELECT-only.
REVOKE ALL ON public.vw_device_heartbeat_status FROM service_role;
GRANT SELECT ON public.vw_device_heartbeat_status TO service_role;

COMMIT;
