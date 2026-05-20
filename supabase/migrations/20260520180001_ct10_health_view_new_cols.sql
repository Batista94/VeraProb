-- ── Migration 20260520180001 ─────────────────────────────────────────────────
-- CT10: Adiciona 4 novas colunas + allowed_domains à super_admin_tenant_health_view.
--
-- Colunas adicionadas:
--   clock_drift_tolerance_s  — Motor Forense (CT10)
--   data_retention_days      — Compliance (CT10)
--   connection_pool_limit    — Infra (CT10)
--   storage_quota_gb         — Infra (CT10)
--   allowed_domains          — Segurança (movida para aba Configuração)
--
-- Invariants:
--   INV-3  — additive only; nenhuma coluna removida.
--   INV-6  — sem colunas datetime novas; existentes preservadas.
--   INV-22 — security_invoker = true mantido.
--   INV-24 — GRANT apenas para service_role.
--
-- Idempotency: DROP VIEW IF EXISTS + CREATE VIEW é seguro.
-- DEVE rodar APÓS 20260520180000 (colunas já existem).
-- ─────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.super_admin_tenant_health_view;

CREATE VIEW public.super_admin_tenant_health_view
  WITH (security_invoker = true)
AS
SELECT
  o.id,
  o.name,
  o.legal_name,
  o.cnpj,
  o.created_at,
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
  o.allowed_domains,
  -- CT10 — Motor Forense, Compliance, Infraestrutura
  o.clock_drift_tolerance_s,
  o.data_retention_days,
  o.connection_pool_limit,
  o.storage_quota_gb,
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

-- INV-24: apenas service_role (Edge Function proxy) pode consultar esta view.
REVOKE ALL   ON public.super_admin_tenant_health_view FROM PUBLIC;
REVOKE ALL   ON public.super_admin_tenant_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_health_view TO service_role;
