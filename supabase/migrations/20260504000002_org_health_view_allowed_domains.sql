-- =============================================================================
-- Phase 10: Add allowed_domains to super_admin_tenant_health_view
-- =============================================================================
-- Recreates the view to expose o.allowed_domains so the SuperAdmin panel
-- can display and edit the domain whitelist in TenantConfigTab.
--
-- Pattern: DROP VIEW IF EXISTS + CREATE VIEW WITH (security_invoker = true)
-- matches the project migration convention (see 20260501100000_*.sql).
-- service_role bypasses RLS and view-level grants automatically.
-- =============================================================================

DROP VIEW IF EXISTS public.super_admin_tenant_health_view;

CREATE VIEW public.super_admin_tenant_health_view
  WITH (security_invoker = true)
AS
SELECT
  o.id,
  o.name,
  o.legal_name,
  o.plan_type,
  o.is_active,
  o.status,
  o.max_vehicles,
  o.max_active_contracts,
  o.capabilities,
  o.tool_cost_cents,
  o.dwell_time_seconds,
  o.billing_day,
  o.contact_email,
  o.external_id,
  o.organization_type,
  o.updated_at,
  o.cnpj,
  o.created_at,
  o.allowed_domains,                                              -- NEW
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                         AS active_contract_count,
  MAX(cf.gps_timestamp)                                        AS last_telemetry_at,
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
GROUP BY o.id, o.cnpj, o.created_at, o.allowed_domains;

REVOKE ALL  ON public.super_admin_tenant_health_view FROM PUBLIC;
REVOKE ALL  ON public.super_admin_tenant_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_health_view TO service_role;
