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
-- NOTE: `is_active` is a GENERATED ALWAYS column (status = 'ACTIVE') since
-- migration 20260427010001_org_status_enum.sql — do NOT insert it explicitly.
-- `status` defaults to 'ACTIVE', so is_active will be TRUE automatically.
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
)
VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    'Org Alpha (Test Tenant A)',
    'Alpha Logística S.A.',
    '00000000000191',
    'America/Sao_Paulo',
    'BRL',
    'enterprise',
    1000,
    50,
    15000,
    300,
    15,
    'billing@org-alpha.com',
    'EXT_ALPHA_001',
    'LOGISTICS',
    ARRAY['org-alpha.com', 'veraprob.dev']
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'Org Beta (Test Tenant B)',
    'Beta Transportes Ltda.',
    '00000000000272',
    'America/Sao_Paulo',
    'BRL',
    'enterprise',
    1000,
    50,
    15000,
    300,
    15,
    'billing@org-beta.com',
    'EXT_BETA_002',
    'TRANSPORT',
    ARRAY['org-beta.com', 'veraprob.dev']
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    'Org Gamma (Test Tenant C)',
    'Gamma Distribuidora S.A.',
    '00000000000353',
    'America/Sao_Paulo',
    'BRL',
    'enterprise',
    1000,
    50,
    15000,
    300,
    15,
    'billing@org-gamma.com',
    'EXT_GAMMA_003',
    'DISTRIBUTION',
    ARRAY['org-gamma.com', 'veraprob.dev']
  )
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  legal_name = EXCLUDED.legal_name,
  cnpj = EXCLUDED.cnpj,
  timezone = EXCLUDED.timezone,
  currency_code = EXCLUDED.currency_code,
  plan_type = EXCLUDED.plan_type,
  max_vehicles = EXCLUDED.max_vehicles,
  max_active_contracts = EXCLUDED.max_active_contracts,
  tool_cost_cents = EXCLUDED.tool_cost_cents,
  dwell_time_seconds = EXCLUDED.dwell_time_seconds,
  billing_day = EXCLUDED.billing_day,
  contact_email = EXCLUDED.contact_email,
  external_id = EXCLUDED.external_id,
  organization_type = EXCLUDED.organization_type,
  allowed_domains = EXCLUDED.allowed_domains;

-- ── 1.b Seed Default Tenant Roles ─────────────────────────────────────────────
DO $$
DECLARE
  v_org_id UUID;
BEGIN
  FOR v_org_id IN SELECT id FROM public.organizations LOOP
    PERFORM public._seed_default_tenant_roles(v_org_id);
  END LOOP;
END;
$$;


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
-- valid_from/until cobre ±1 ano a partir do reset — suficiente para testes locais.
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

-- ── 5. Vehicles ───────────────────────────────────────────────────────────────
-- Seed vehicles for CT04 (active vehicle gate) and CT05 (telemetry simulation).
-- UUIDs fixos para referenciar em scripts de teste.
INSERT INTO public.vehicles (
  id,
  organization_id,
  plate,
  model,
  capacity,
  status,
  device_serial,
  external_id
)
VALUES
  (
    '00000000-0000-0000-0000-a00000000001',
    '00000000-0000-0000-0000-000000000001',
    'TST-0001',
    'Ônibus Teste Org A',
    40,
    'available',
    'DEV-SERIAL-001',
    'EXT-VEH-001'
  ),
  (
    '00000000-0000-0000-0000-b00000000002',
    '00000000-0000-0000-0000-000000000002',
    'TST-0002',
    'Ônibus Teste Org B',
    40,
    'available',
    'DEV-SERIAL-002',
    'EXT-VEH-002'
  )
ON CONFLICT (organization_id, plate) DO NOTHING;
