-- =============================================================================
-- Fix CT10: Add cnpj + created_at to super_admin_tenant_health_view
-- =============================================================================
-- Root cause: The view SELECT omitted o.cnpj and o.created_at, so the Edge
-- Function never returned those fields and TenantHealthView.cnpj was always
-- null, causing the UI to display "Não informado" even when the value existed
-- in the organizations table.
--
-- Both columns exist on public.organizations (cnpj text nullable,
-- created_at timestamptz not null) and were already mapped in:
--   - TenantHealthSnapshot.fromJson  (line 91 / 92)
--   - TenantHealthView.fromJson      (line 151 / 152)
-- The only missing link was the DB view and the proxy select list.
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
  -- CT10 fix: core identity fields previously missing from this view
  o.cnpj,
  o.created_at,
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
GROUP BY o.id;

-- Restore grants: DROP VIEW above erases all previous grants.
-- Only service_role (Edge Function proxy) may query the view directly.
REVOKE ALL  ON public.super_admin_tenant_health_view FROM PUBLIC;
REVOKE ALL  ON public.super_admin_tenant_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_health_view TO service_role;
