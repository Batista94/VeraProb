-- =============================================================================
-- Migration: Restore cnpj + created_at to super_admin_tenant_health_view
-- =============================================================================
-- Regression fix for 20260705000002_superadmin_ct_fixes.sql which omitted
-- o.cnpj and o.created_at when it DROP+CREATE'd the view.
--
-- Must run AFTER all other 20260706 migrations (000001–000007) to be the
-- authoritative final definition of the view.
--
-- Invariants:
--   INV-3  — view is audit surface; column removal = data loss regression.
--   INV-6  — created_at must be TIMESTAMPTZ (UTC). o.created_at is TIMESTAMPTZ.
--   INV-22 — security_invoker = true preserved (multi-tenancy guard).
--   INV-24 — GRANT SELECT only to service_role; revoke PUBLIC + authenticated.
--
-- Idempotency: DROP VIEW IF EXISTS + CREATE VIEW is safe — this view has no
-- dependent views or materialized views. The GRANT block re-applies after DROP
-- resets permissions.
-- =============================================================================

DROP VIEW IF EXISTS public.super_admin_tenant_health_view;

CREATE VIEW public.super_admin_tenant_health_view
  WITH (security_invoker = true)
AS
SELECT
  o.id,
  o.name,
  o.legal_name,
  o.cnpj,                          -- restored (INV-3)
  o.created_at,                    -- restored as TIMESTAMPTZ (INV-3, INV-6)
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
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                        AS active_contract_count,
  MAX(cf.gps_timestamp)                                       AS last_telemetry_at,
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

-- INV-24: only service_role (Edge Function proxy) may query this view.
REVOKE ALL   ON public.super_admin_tenant_health_view FROM PUBLIC;
REVOKE ALL   ON public.super_admin_tenant_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_health_view TO service_role;
