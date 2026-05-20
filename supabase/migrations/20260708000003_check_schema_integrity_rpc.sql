-- ── Migration 20260708000003 ─────────────────────────────────────────────────
-- Cria a função public.check_schema_integrity(p_org_id UUID).
--
-- Consumidores:
--   Edge Function super-admin-proxy, action check_schema_integrity
--   (linha 306: serviceClient.rpc("check_schema_integrity", { p_org_id: orgId }))
--
-- Lógica:
--   1. Conta quantas das tabelas críticas existem em information_schema.tables
--      para o schema public (tabelas esperadas: contracts, canonical_facts,
--      operational_alerts, user_roles).
--   2. Deriva status: 4/4 → compliant; 2-3/4 → minor_drift; <2/4 → critical_drift.
--   3. Computa schema_version como YYYY-MM-DD (hoje em UTC), preservando valor
--      já existente se não for 'unknown'.
--   4. UPDATE organizations SET ... WHERE id = p_org_id (single-row por PK — sem bloqueio).
--   5. Retorna JSONB com schema_integrity_status, schema_version, last_check_at.
--
-- Invariants:
--   INV-3  — organizations não é ledger; UPDATE é permitido (quota updates já existem).
--   INV-6  — NOW() AT TIME ZONE 'UTC' para todos os timestamps.
--   INV-7  — JSONB tipado; sem RECORD anônimo.
--   INV-DB — UPDATE em single-row por PK; sem DDL bloqueante.
--
-- Segurança:
--   SECURITY DEFINER — bypass RLS para leitura de information_schema e UPDATE em organizations.
--   GRANT EXECUTE apenas para service_role (Edge Function usa service_key).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.check_schema_integrity(p_org_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, information_schema
AS $$
DECLARE
  v_expected_tables TEXT[]  := ARRAY['contracts', 'canonical_facts', 'operational_alerts', 'user_roles'];
  v_table_name      TEXT;
  v_present_count   INT     := 0;
  v_status          TEXT;
  v_version         TEXT;
  v_existing_version TEXT;
  v_now_utc         TIMESTAMPTZ;
  v_result          JSONB;
BEGIN
  -- 1. INV-6: captura timestamp UTC canônico uma única vez
  v_now_utc := NOW() AT TIME ZONE 'UTC';

  -- 2. Contar quantas tabelas críticas existem em public schema
  FOREACH v_table_name IN ARRAY v_expected_tables
  LOOP
    IF EXISTS (
      SELECT 1
      FROM information_schema.tables t
      WHERE t.table_schema = 'public'
        AND t.table_name   = v_table_name
        AND t.table_type   = 'BASE TABLE'
    ) THEN
      v_present_count := v_present_count + 1;
    END IF;
  END LOOP;

  -- 3. Derivar status de integridade
  --    4/4 → compliant | 2-3/4 → minor_drift | 0-1/4 → critical_drift
  IF v_present_count = array_length(v_expected_tables, 1) THEN
    v_status := 'compliant';
  ELSIF v_present_count >= 2 THEN
    v_status := 'minor_drift';
  ELSE
    v_status := 'critical_drift';
  END IF;

  -- 4. Preservar schema_version se já calculado (não 'unknown')
  SELECT schema_version
    INTO v_existing_version
    FROM public.organizations
   WHERE id = p_org_id;

  v_version := COALESCE(
    NULLIF(v_existing_version, 'unknown'),
    to_char(v_now_utc, 'YYYY-MM-DD')
  );

  -- 5. UPDATE single-row por PK (INV-3: organizations não é ledger)
  UPDATE public.organizations
     SET schema_integrity_status = v_status,
         schema_version          = v_version,
         last_schema_check_at    = v_now_utc
   WHERE id = p_org_id;

  -- 6. Retornar JSONB com os campos esperados por TenantTechnicalHealthView.fromJson
  v_result := jsonb_build_object(
    'schema_integrity_status', v_status,
    'schema_version',          v_version,
    'last_check_at',           v_now_utc
  );

  RETURN v_result;
END;
$$;

-- INV-22: apenas service_role (Edge Function com service_key) pode executar.
-- authenticated NÃO deve ter acesso — RPC não valida JWT super_admin claim porque
-- é invocado exclusivamente pelo proxy autenticado com service_key.
REVOKE ALL     ON FUNCTION public.check_schema_integrity(UUID) FROM PUBLIC;
REVOKE ALL     ON FUNCTION public.check_schema_integrity(UUID) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.check_schema_integrity(UUID) TO service_role;
