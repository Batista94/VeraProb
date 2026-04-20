-- ============================================================
-- veraprob — Bootstrap Dev Seed (Full)
-- ============================================================
-- DEV ONLY. Nunca executar em staging ou produção.
-- Safe to re-run: todos os INSERTs usam ON CONFLICT DO NOTHING.
--
-- Cria:
--   • 2 organizations (Org A + Org B) com UUIDs fixos
--   • 2 auth.users com senha conhecida (para k6 e testes locais)
--   • 2 user_roles (TENANT_ADMIN por org — JWT hook lê desta tabela)
--   • 2 contracts ativos (um por org, com UUIDs fixos para k6 env vars)
--
-- Credenciais de teste:
--   Org A — admin-a@veraprob.dev / veraprob123!
--   Org B — admin-b@veraprob.dev / veraprob123!
--
-- UUIDs fixos (para uso nos scripts k6):
--   ORG_A_ID       = 00000000-0000-0000-0000-000000000001
--   ORG_B_ID       = 00000000-0000-0000-0000-000000000002
--   CONTRACT_A_ID  = 00000000-0000-0000-0000-ca0000000001
--   CONTRACT_B_ID  = 00000000-0000-0000-0000-cb0000000001
-- ============================================================

-- ── 1. Organizations ──────────────────────────────────────────────────────────
INSERT INTO public.organizations (id, name, is_active)
VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    'Org Alpha (Test Tenant A)',
    true
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'Org Beta (Test Tenant B)',
    true
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    'Org Gamma (Test Tenant C)',
    true
  )
ON CONFLICT (id) DO NOTHING;


-- ── 2. Auth Users + User Roles ────────────────────────────────────────────────
-- NÃO inserimos em auth.users aqui.
-- Motivo: o schema de auth.users muda entre versões do Supabase CLI (GoTrue).
-- Inserção direta quebraria com campos NOT NULL variantes (is_sso_user,
-- instance_id, confirmation_token, etc.) dependendo da versão instalada.
--
-- Os usuários de teste e os user_roles são criados pelo helper script
-- APÓS o db reset, via Admin API (POST /auth/v1/admin/users com service_role key).
-- Isso garante compatibilidade com qualquer versão do Supabase CLI.
--
-- Execute: node scripts/k6_get_test_jwts.mjs
-- O script cria os usuários, insere os user_roles e imprime os JWTs.


-- ── 4. Active Contracts ───────────────────────────────────────────────────────
-- IDs fixos para que os env vars do k6 possam ser hardcoded no helper script.
-- valid_from/until cobre ±1 ano a partir do reset — suficiente para MVP.
-- Não tem FK para contractors — contractor_name é TEXT livre nesta tabela.
INSERT INTO public.contracts (
  id,
  organization_id,
  name,
  contractor_name,
  valid_from_utc,
  valid_until_utc,
  status,
  activated_at_utc
)
VALUES
  (
    '00000000-0000-0000-0000-ca0000000001',
    '00000000-0000-0000-0000-000000000001',
    'Contrato Teste Org A',
    'Contratante Alpha Ltda',
    now() - interval '30 days',
    now() + interval '335 days',
    'active',
    now() - interval '30 days'
  ),
  (
    '00000000-0000-0000-0000-cb0000000001',
    '00000000-0000-0000-0000-000000000002',
    'Contrato Teste Org B',
    'Contratante Beta Ltda',
    now() - interval '30 days',
    now() + interval '335 days',
    'active',
    now() - interval '30 days'
  )
ON CONFLICT (id) DO NOTHING;
