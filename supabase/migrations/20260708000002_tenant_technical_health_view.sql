-- ── Migration 20260708000002 ─────────────────────────────────────────────────
-- Cria a VIEW public.super_admin_tenant_technical_health_view.
--
-- Consumidores:
--   Edge Function super-admin-proxy, action get_tenant_technical_health
--   (linha 277: .from("super_admin_tenant_technical_health_view").select("*").eq("id", orgId))
--
-- Colunas expostas (contrato com TenantTechnicalHealthView.fromJson):
--   id                      UUID   — organizations.id
--   replication_status      TEXT   — derivado do último gps_timestamp em canonical_facts
--   schema_integrity_status TEXT   — organizations.schema_integrity_status
--   schema_version          TEXT   — organizations.schema_version
--   last_check_at           TIMESTAMPTZ — organizations.last_schema_check_at
--
-- Invariants:
--   INV-6  — sem DEFAULT em colunas TIMESTAMPTZ; NOW() AT TIME ZONE 'UTC' nos thresholds.
--   INV-22 — security_invoker = true; GRANT apenas para service_role.
--   INV-DB — DROP VIEW IF EXISTS + CREATE VIEW é seguro (sem bloqueio).
--
-- Idempotência: DROP VIEW IF EXISTS + CREATE VIEW é seguro para re-execução.
-- DEVE rodar APÓS 20260708000001 (colunas schema_integrity_status/schema_version/last_schema_check_at devem existir).
-- ─────────────────────────────────────────────────────────────────────────────

DROP VIEW IF EXISTS public.super_admin_tenant_technical_health_view;

CREATE VIEW public.super_admin_tenant_technical_health_view
  WITH (security_invoker = true)
AS
SELECT
  o.id,
  -- INV-6: thresholds calculados em UTC para evitar desvio de timezone de servidor
  CASE
    WHEN MAX(cf.gps_timestamp) > (NOW() AT TIME ZONE 'UTC') - INTERVAL '5 minutes'
      THEN 'healthy'
    WHEN MAX(cf.gps_timestamp) > (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 hour'
      THEN 'delayed'
    WHEN MAX(cf.gps_timestamp) IS NULL
      THEN 'unknown'
    ELSE 'failed'
  END                              AS replication_status,
  o.schema_integrity_status,
  o.schema_version,
  o.last_schema_check_at           AS last_check_at
FROM public.organizations o
LEFT JOIN public.canonical_facts cf
  ON cf.organization_id = o.id
GROUP BY
  o.id,
  o.schema_integrity_status,
  o.schema_version,
  o.last_schema_check_at;

-- INV-22: apenas service_role (Edge Function proxy com service_key) pode consultar.
-- authenticated e anon NÃO devem ter acesso a dados cross-tenant desta view.
REVOKE ALL   ON public.super_admin_tenant_technical_health_view FROM PUBLIC;
REVOKE ALL   ON public.super_admin_tenant_technical_health_view FROM authenticated;
GRANT  SELECT ON public.super_admin_tenant_technical_health_view TO service_role;
