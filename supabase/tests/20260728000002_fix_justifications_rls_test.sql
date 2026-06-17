BEGIN;
SELECT plan(6);

-- =============================================================================
-- Test: fix_justifications_rls — verifica que as políticas RLS usam o caminho
-- JWT canônico: auth.jwt() -> 'app_metadata' ->> 'org_id' (INV-2/INV-22)
--
-- Estratégia: verificar as definições das políticas em pg_policies para evitar
-- dependência frágil de SET LOCAL ROLE + GUC resets no ambiente pgTAP.
-- =============================================================================

-- TC1: Política SELECT cj_select_own_org usa app_metadata ->> org_id (INV-2)
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractor_justifications'
      AND policyname = 'cj_select_own_org'
      AND qual ILIKE '%app_metadata%org_id%'
  ),
  'TC1/INV-2: cj_select_own_org USING usa app_metadata -> org_id (não jwt ->> organization_id)'
);

-- TC2: Política SELECT não usa o caminho legado direto jwt ->> organization_id
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractor_justifications'
      AND policyname = 'cj_select_own_org'
      AND qual ILIKE '%jwt() ->>%organization_id%'
  ),
  'TC2/INV-2: cj_select_own_org USING NÃO usa caminho legado jwt ->> organization_id'
);

-- TC3: Política INSERT cj_insert_operator usa app_metadata ->> org_id
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractor_justifications'
      AND policyname = 'cj_insert_operator'
      AND with_check ILIKE '%app_metadata%org_id%'
  ),
  'TC3/INV-2: cj_insert_operator WITH CHECK usa app_metadata -> org_id'
);

-- TC4: Política INSERT cj_insert_operator usa roles canônicos TENANT_ADMIN/OPERATOR
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractor_justifications'
      AND policyname = 'cj_insert_operator'
      AND with_check ILIKE '%TENANT_ADMIN%'
  ),
  'TC4/INV-2: cj_insert_operator WITH CHECK usa role canônico TENANT_ADMIN (não ''admin'')'
);

-- TC5: Política SELECT cj_select_own_org usa roles canônicos (TENANT_ADMIN/OPERATOR/AUDITOR)
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractor_justifications'
      AND policyname = 'cj_select_own_org'
      AND qual ILIKE '%TENANT_ADMIN%'
  ),
  'TC5/INV-2: cj_select_own_org USING usa role canônico TENANT_ADMIN (não ''admin'')'
);

-- TC6: Política cj_insert_service escopada apenas para service_role
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractor_justifications'
      AND policyname = 'cj_insert_service'
      AND roles = ARRAY['service_role']::name[]
  ),
  'TC6: cj_insert_service está escopada exclusivamente ao service_role (não ao authenticated)'
);

SELECT * FROM finish();
ROLLBACK;
