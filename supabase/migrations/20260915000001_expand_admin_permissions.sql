-- =============================================================================
-- Migration: Expand administrative permissions (users, roles:read, org:manage)
-- =============================================================================
-- Context: 
-- The permission `roles:manage` was acting as a monolithic gate for the entire
-- administration hub (Users, Roles, and Org Settings). In Tier-1 enterprise 
-- systems, operations managers (Validador) need to invite their own team 
-- members (`users:manage`) and view roles (`roles:read`), but must NOT be able 
-- to mutate system RBAC (`roles:manage`) or integrations (`org:manage`).
--
-- Actions:
-- 1. Insert 3 new granular permissions into `tenant_permissions`.
-- 2. Retroactively grant `users:manage`, `roles:read`, and `org:manage` to 
--    any tenant_role that currently has `roles:manage`, ensuring zero regression.
--
-- Invariants:
-- INV-DB: Append-only schema change.
-- =============================================================================

-- ── 1. Insert new granular permissions ────────────────────────────────────────

INSERT INTO public.tenant_permissions
  (key, module, action, label_pt, description, is_sensitive, is_scopable)
VALUES
  ('users:manage', 'users', 'manage', 'Gerenciar equipe',      'Convidar, remover e gerenciar usuários da organização', true, false),
  ('roles:read',   'roles', 'read',   'Visualizar perfis',     'Visualizar aba de acessos e perfis (somente leitura)',  false, false),
  ('org:manage',   'org',   'manage', 'Gerenciar organização', 'Gerenciar integrações, webhooks e configurações',     true, false)
ON CONFLICT (key) DO NOTHING;

-- ── 2. Retroactive grants (Zero Regression) ───────────────────────────────────
-- Any existing profile that has `roles:manage` gets the new permissions automatically
-- so existing admins do not lose access to the user management and org settings.

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
SELECT tenant_role_id, 'users:manage'
FROM public.tenant_role_permissions
WHERE permission_key = 'roles:manage'
ON CONFLICT (tenant_role_id, permission_key) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
SELECT tenant_role_id, 'roles:read'
FROM public.tenant_role_permissions
WHERE permission_key = 'roles:manage'
ON CONFLICT (tenant_role_id, permission_key) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key)
SELECT tenant_role_id, 'org:manage'
FROM public.tenant_role_permissions
WHERE permission_key = 'roles:manage'
ON CONFLICT (tenant_role_id, permission_key) DO NOTHING;
