-- =============================================================================
-- pgTAP: Tenant RBAC JWT hook (Pilar 1.2) — migration 20260909000002
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009a1', 'RBAC Org A', 'RBAC Org A SA', '000000000009a1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rbac-a@test.com', 'EXT_RBAC_A', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-0000000009b1', 'RBAC Org B', 'RBAC Org B SA', '000000000009b1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rbac-b@test.com', 'EXT_RBAC_B', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

SET LOCAL session_replication_role = replica;
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
  ('00000000-0000-0000-0000-0000000009a9', '00000000-0000-0000-0000-0000000009a1', 'TENANT_ADMIN'),
  ('00000000-0000-0000-0000-0000000009a2', '00000000-0000-0000-0000-0000000009a1', 'OPERATOR')
ON CONFLICT (user_id) DO UPDATE
  SET organization_id = EXCLUDED.organization_id, role = EXCLUDED.role;
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.tenant_roles (id, organization_id, name, description, is_system) VALUES
  ('00000000-0000-0000-0000-0000000009c1', '00000000-0000-0000-0000-0000000009a1',
   'Financeiro', 'Leitura financeira + telemetria', false),
  ('00000000-0000-0000-0000-0000000009c2', '00000000-0000-0000-0000-0000000009a1',
   'SLA Ops', 'Operações de sanção', false),
  ('00000000-0000-0000-0000-0000000009c4', '00000000-0000-0000-0000-0000000009a1',
   'Cadastros Expired', 'Grant expirado para teste de hook', false),
  ('00000000-0000-0000-0000-0000000009c3', '00000000-0000-0000-0000-0000000009b1',
   'Org B Role', 'Cross-tenant bait', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key, scope) VALUES
  ('00000000-0000-0000-0000-0000000009c1', 'financial:read', NULL),
  ('00000000-0000-0000-0000-0000000009c1', 'telemetry:read', NULL),
  ('00000000-0000-0000-0000-0000000009c2', 'sla:read', NULL),
  ('00000000-0000-0000-0000-0000000009c4', 'cadastros:write', NULL),
  ('00000000-0000-0000-0000-0000000009c3', 'financial:read', NULL)
ON CONFLICT DO NOTHING;

INSERT INTO public.user_tenant_roles (
  user_id, tenant_role_id, organization_id, valid_from, valid_until, revoked_at
) VALUES
  ('00000000-0000-0000-0000-0000000009a2', '00000000-0000-0000-0000-0000000009c1',
   '00000000-0000-0000-0000-0000000009a1', NOW() - INTERVAL '1 day', NULL, NULL),
  ('00000000-0000-0000-0000-0000000009a2', '00000000-0000-0000-0000-0000000009c2',
   '00000000-0000-0000-0000-0000000009a1', NOW() - INTERVAL '1 day', NULL, NULL)
ON CONFLICT (user_id, tenant_role_id) DO UPDATE
  SET revoked_at = NULL, valid_until = NULL, valid_from = NOW() - INTERVAL '1 day';

INSERT INTO public.user_tenant_roles (
  user_id, tenant_role_id, organization_id, valid_from, valid_until, revoked_at
) VALUES
  ('00000000-0000-0000-0000-0000000009a2', '00000000-0000-0000-0000-0000000009c4',
   '00000000-0000-0000-0000-0000000009a1', NOW() - INTERVAL '10 days', NOW() - INTERVAL '1 day', NULL)
ON CONFLICT (user_id, tenant_role_id) DO UPDATE
  SET valid_until = NOW() - INTERVAL '1 day', revoked_at = NULL;

INSERT INTO public.user_tenant_roles (
  user_id, tenant_role_id, organization_id, valid_from, revoked_at
) VALUES
  ('00000000-0000-0000-0000-0000000009a2', '00000000-0000-0000-0000-0000000009c3',
   '00000000-0000-0000-0000-0000000009b1', NOW() - INTERVAL '5 days', NOW())
ON CONFLICT (user_id, tenant_role_id) DO UPDATE
  SET revoked_at = NOW(), valid_until = NULL;

-- ── Multi-role union ─────────────────────────────────────────────────────────
SELECT is(
  (
    SELECT jsonb_array_length(
      public.custom_access_token_hook(jsonb_build_object(
        'user_id', '00000000-0000-0000-0000-0000000009a2',
        'claims', jsonb_build_object('app_metadata', '{}'::jsonb)
      )) -> 'claims' -> 'app_metadata' -> 'permissions'
    )
  ),
  3,
  'hook unions distinct permissions from two active custom roles'
);

SELECT ok(
  (
    public.custom_access_token_hook(jsonb_build_object(
      'user_id', '00000000-0000-0000-0000-0000000009a2',
      'claims', jsonb_build_object('app_metadata', '{}'::jsonb)
    )) -> 'claims' -> 'app_metadata' -> 'permissions'
  ) ? 'financial:read',
  'hook includes financial:read from role A1');

SELECT is(
  (
    public.custom_access_token_hook(jsonb_build_object(
      'user_id', '00000000-0000-0000-0000-0000000009a9',
      'claims', jsonb_build_object('app_metadata', '{}'::jsonb)
    )) -> 'claims' -> 'app_metadata' -> 'permissions'
  ),
  '["*"]'::jsonb,
  'TENANT_ADMIN receives wildcard permissions'
);

-- ── Expired + revoked grants excluded ─────────────────────────────────────────
SELECT ok(
  NOT (
    public.custom_access_token_hook(jsonb_build_object(
      'user_id', '00000000-0000-0000-0000-0000000009a2',
      'claims', jsonb_build_object('app_metadata', '{}'::jsonb)
    )) -> 'claims' -> 'app_metadata' -> 'permissions'
  ) ? 'cadastros:write',
  'expired valid_until grant excluded from hook aggregate'
);

SELECT ok(
  (
    SELECT count(*)::int
      FROM jsonb_array_elements_text(
        public.custom_access_token_hook(jsonb_build_object(
          'user_id', '00000000-0000-0000-0000-0000000009a2',
          'claims', jsonb_build_object('app_metadata', '{}'::jsonb)
        )) -> 'claims' -> 'app_metadata' -> 'permissions'
      ) AS p(key)
     WHERE p.key = 'financial:read'
  ) = 1,
  'revoked grant does not duplicate financial:read from revoked role');

SELECT has_function('public', 'custom_access_token_hook', ARRAY['jsonb']);

SELECT * FROM finish();
ROLLBACK;
