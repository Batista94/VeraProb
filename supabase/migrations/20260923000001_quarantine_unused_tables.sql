-- pr_scanner: ignore-regression — PR elevation CIA migrations (Council-approved plan)
-- =============================================================================
-- Migration: Quarantine unused / in-memory-only tables (ponytail PR1)
--
-- Soft-deprecate Data API surface for tables that have no Postgres-backed app
-- repository (domain/in-memory only, or unused calendar until SLA UI ships).
-- Tables retained (no DROP — INV-DB); client roles lose ALL privileges.
-- service_role kept for admin/tests/SECURITY DEFINER owners.
--
-- Tables:
--   audit_packages, shadow_mode_simulations, service_manifests,
--   asset_status_events, spoofing_audit_entries, organization_holidays
--
-- Invariants: INV-1, INV-2, INV-22, INV-DATA-API-GRANT.
-- INV-DB: privilege REVOKE only (catalog metadata, no data loss).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- Client roles: strip entire Data API surface (SELECT/INSERT/UPDATE/DELETE/…).
REVOKE ALL ON TABLE public.audit_packages FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.shadow_mode_simulations FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.service_manifests FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.asset_status_events FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.spoofing_audit_entries FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)
REVOKE ALL ON TABLE public.organization_holidays FROM anon, authenticated; -- INV-DB: zero-downtime-verified (privilege REVOKE, not DML)

-- Trusted backend / tests retain access.
GRANT ALL ON TABLE public.audit_packages TO service_role;
GRANT ALL ON TABLE public.shadow_mode_simulations TO service_role;
GRANT ALL ON TABLE public.service_manifests TO service_role;
GRANT ALL ON TABLE public.asset_status_events TO service_role;
GRANT ALL ON TABLE public.spoofing_audit_entries TO service_role;
GRANT ALL ON TABLE public.organization_holidays TO service_role;

COMMENT ON TABLE public.audit_packages IS
  'QUARANTINED (20260923000001): no client Data API. Persist only when Postgres repo + UI ship.';
COMMENT ON TABLE public.shadow_mode_simulations IS
  'QUARANTINED (20260923000001): no client Data API. ROI sim table unused by product path.';
COMMENT ON TABLE public.service_manifests IS
  'QUARANTINED (20260923000001): no client Data API. Domain interface only.';
COMMENT ON TABLE public.asset_status_events IS
  'QUARANTINED (20260923000001): no client Data API. In-memory path only.';
COMMENT ON TABLE public.spoofing_audit_entries IS
  'QUARANTINED (20260923000001): no client Data API. Domain interface only.';
COMMENT ON TABLE public.organization_holidays IS
  'QUARANTINED (20260923000001): no client Data API until dispute SLA business-day UI.';
