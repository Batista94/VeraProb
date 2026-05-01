-- pr_scanner: ignore-regression
--
 ============================================================
-- veraprob — Sprint 5.13 Bloco 5.1: CSE RLS Fix (INV-10)
-- ============================================================
-- REASON:
--   contractual_service_executions tinha bootstrap antipattern:
--   RLS usava (auth.jwt() ->> 'sub') — Org UUID ≠ User UUID com ≥ 2 usuários
--   por tenant → erro 42501 em todo publish B2B.
--
-- FIX:
--   1. ADD COLUMN IF NOT EXISTS organization_id (defensivo)
--   2. ENABLE ROW LEVEL SECURITY (idempotente)
--   3. DROP todas as policies existentes (nome-agnóstico via DO block)
--   4. CREATE policies corretas via JWT claim app_metadata.org_id
--
-- INVARIANT ENFORCED: INV-10
--   All RLS tenant isolation policies must use
--   auth.jwt() ->> 'organization_id', never (auth.jwt() ->> 'sub').
--   The pattern organization_id = (auth.jwt() ->> 'sub') is a bootstrap
--   antipattern that breaks with >= 2 users per organization.
-- ============================================================

-- 1. Garantir coluna organization_id
--    (defensivo — Bloco 1.1 foi aplicado via Supabase SQL Editor)
ALTER TABLE public.contractual_service_executions
  ADD COLUMN IF NOT EXISTS organization_id UUID;

-- 2. Habilitar RLS (idempotente)
ALTER TABLE public.contractual_service_executions ENABLE ROW LEVEL SECURITY;

-- 3. Dropar TODAS as policies existentes na tabela
--    (independente do nome — elimina qualquer policy (auth.jwt() ->> 'sub') residual)
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'contractual_service_executions'
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS %I ON public.contractual_service_executions',
      pol.policyname
    );
  END LOOP;
END;
$$;

-- 4. Criar policies corretas com JWT claim (INV-10 enforced)

-- SELECT: operador lê apenas SETs da sua própria org
CREATE POLICY "CSE tenant isolation select"
  ON public.contractual_service_executions
  FOR SELECT TO authenticated
  USING (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- INSERT: publish de plano só insere SETs da própria org
CREATE POLICY "CSE tenant isolation insert"
  ON public.contractual_service_executions
  FOR INSERT TO authenticated
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);

-- NOTE: Sem UPDATE/DELETE — CSE é append-only por design.
-- Remoção só ocorre via CASCADE de plan_declarations
-- (proibida pela camada de aplicação).
