-- =============================================================================
-- Phase 9.2 — SuperAdmin Tenant Health View
-- =============================================================================
-- Cross-tenant read model accessible ONLY via service_role client.
-- No GRANT to authenticated/anon — PostgREST will not expose this view.
-- SuperAdmin Flutter client uses SupabaseClient(url, serviceRoleKey) directly.
--
-- R1 column name corrections applied:
--   - operational_alerts.severity = 'CRITICAL' (uppercase per CHECK constraint)
--   - operational_alerts.resolved_at_utc (actual column name)
-- =============================================================================

CREATE OR REPLACE VIEW public.super_admin_tenant_health_view AS
SELECT
  o.id,
  o.name,
  o.legal_name,
  o.plan_type,
  o.is_active,
  o.max_vehicles,
  o.max_active_contracts,
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                     AS active_contract_count,
  MAX(cf.gps_timestamp)                                    AS last_telemetry_at,
  COUNT(DISTINCT a.id)
    FILTER (WHERE a.severity = 'CRITICAL' AND a.resolved_at_utc IS NULL)
                                                           AS open_critical_alert_count
FROM public.organizations o
LEFT JOIN public.contracts c
  ON c.organization_id = o.id
LEFT JOIN public.canonical_facts cf
  ON cf.organization_id = o.id
LEFT JOIN public.operational_alerts a
  ON a.organization_id = o.id
GROUP BY o.id;

-- Intentionally NO GRANT to authenticated or anon.
-- service_role bypasses RLS and view-level grants automatically.
-- Tenant users cannot query this view via PostgREST.
