-- =============================================================================
-- Phase 9.2 — SuperAdmin RLS Hardening (defense-in-depth)
-- =============================================================================
-- Adiciona guarda de exclusão de super_admin na policy SELECT de organizations.
-- Impede que JWT com super_admin: true leia dados de tenant via client anon (D3).
-- SuperAdmin DEVE usar o client service_role para acessar organizations.
--
-- Correções em relação ao plano original:
--   - organizations usa 'id' como PK (não 'organization_id')
--   - Policy existente chama-se "Tenant Isolation: organizations"
--     (criada em 20260317000001_rls_jwt_path_unification.sql)
--   - Apenas SELECT policy existe para authenticated (sem write policies)
-- =============================================================================

-- 1. Remover a policy SELECT existente (nome exato do migration 20260317000001)
DROP POLICY IF EXISTS "Tenant Isolation: organizations" ON public.organizations;

-- 2. Recriar com guarda super_admin
--    'id' é a PK de organizations; JWT org_id é comparado com 'id', não 'organization_id'
CREATE POLICY "Tenant Isolation: organizations"
  ON public.organizations
  FOR SELECT
  TO authenticated
  USING (
    id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'super_admin') IS DISTINCT FROM 'true'
  );
