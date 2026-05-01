-- =============================================================================
-- Add cnpj and created_at to SuperAdmin Tenant Health View
-- =============================================================================
-- Exposes o.cnpj and o.created_at in the view so the Flutter SuperAdmin panel
-- can display immutable identity fields (Slug, CNPJ, Data de Criação) in the
-- TenantConfigTab without an extra query.
--
-- Both columns come directly from public.organizations and are NOT aggregated.
-- Although PostgreSQL allows omitting them from GROUP BY (functional dependency
-- on PK o.id), we list them explicitly for enterprise audit clarity and to
-- avoid ambiguity in future JOIN refactors.
--
-- No GRANT to authenticated or anon — service_role bypasses RLS and
-- view-level grants automatically.
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
  o.cnpj,                                                     -- NEW
  o.created_at,                                                -- NEW
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                       AS active_contract_count,
  MAX(cf.gps_timestamp)                                      AS last_telemetry_at,
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
GROUP BY o.id, o.cnpj, o.created_at;

-- Restore grants: DROP VIEW above erases all previous grants.
-- Only service_role (Edge Function proxy) may query the view directly.
REVOKE ALL  ON public.super_admin_tenant_health_view FROM PUBLIC;
REVOKE ALL  ON public.super_admin_tenant_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_health_view TO service_role;
