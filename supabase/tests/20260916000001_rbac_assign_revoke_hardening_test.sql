-- =============================================================================
-- pgTAP: RBAC Assign/Revoke Hardening (Case 2) — 20260916000001
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ── Fixtures (superuser, pre-RLS) ────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, timezone, plan_type
) VALUES (
  '00000000-0000-0000-0000-000000000aa1', 'Org 1', 'America/Sao_Paulo', 'enterprise'
) ON CONFLICT DO NOTHING;

INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-000000000aa2', '00000000-0000-0000-0000-000000000aa1', 'Administrador', true),
  ('00000000-0000-0000-0000-000000000aa3', '00000000-0000-0000-0000-000000000aa1', 'Validador', false),
  ('00000000-0000-0000-0000-000000000aa4', '00000000-0000-0000-0000-000000000aa1', 'Operador', false)
ON CONFLICT DO NOTHING;

INSERT INTO public.tenant_permissions (key, module, action, label_pt, description, is_sensitive, is_scopable) VALUES
  ('roles:manage', 'system', 'manage', 'Roles', 'Roles', true, false),
  ('sensitive:read', 'system', 'read', 'Sensitive', 'Sensitive', true, false)
ON CONFLICT DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-000000000aa2', 'roles:manage'),
  ('00000000-0000-0000-0000-000000000aa2', 'sensitive:read'),
  ('00000000-0000-0000-0000-000000000aa3', 'roles:manage'),
  ('00000000-0000-0000-0000-000000000aa4', 'roles:manage')
ON CONFLICT DO NOTHING;

INSERT INTO auth.users (id, aud, role, email) VALUES 
  ('00000000-0000-0000-0000-0000000000aa', 'authenticated', 'authenticated', 'a@a.com'),
  ('00000000-0000-0000-0000-0000000000ab', 'authenticated', 'authenticated', 'b@b.com'),
  ('00000000-0000-0000-0000-0000000000ac', 'authenticated', 'authenticated', 'c@c.com'),
  ('00000000-0000-0000-0000-0000000000ad', 'authenticated', 'authenticated', 'd@d.com')
ON CONFLICT DO NOTHING;

SET LOCAL session_replication_role = replica;
INSERT INTO public.user_roles (user_id, organization_id, role, is_active) VALUES
  ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000aa1', 'TENANT_ADMIN', true),
  ('00000000-0000-0000-0000-0000000000ab', '00000000-0000-0000-0000-000000000aa1', 'OPERATOR', true),
  ('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000aa1', 'OPERATOR', true),
  ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000aa1', 'TENANT_ADMIN', true)
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;
SET LOCAL session_replication_role = DEFAULT;

SET LOCAL session_replication_role = replica;
INSERT INTO public.user_tenant_roles (user_id, tenant_role_id, organization_id) VALUES
  ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000aa2', '00000000-0000-0000-0000-000000000aa1'),
  -- Fallback role for Admin 1 so LastProfileGuard doesn't fire when Administrador is revoked
  ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000aa4', '00000000-0000-0000-0000-000000000aa1'),
  ('00000000-0000-0000-0000-0000000000ab', '00000000-0000-0000-0000-000000000aa3', '00000000-0000-0000-0000-000000000aa1'),
  ('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000aa4', '00000000-0000-0000-0000-000000000aa1'),
  ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000aa2', '00000000-0000-0000-0000-000000000aa1'),
  -- Fallback role for Admin 2 so LastProfileGuard doesn't fire before last-admin guard
  ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000aa4', '00000000-0000-0000-0000-000000000aa1')
ON CONFLICT (user_id, tenant_role_id) DO NOTHING;
SET LOCAL session_replication_role = DEFAULT;

-- ── Tests ──────────────────────────────────────────────────────────────────
-- Test 1: Guard _rbac_assert_can_grant_role
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000ab","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000aa1","role":"OPERATOR","permissions":["roles:manage"]}}';

SELECT is(
  (SELECT COUNT(*) FROM public.tenant_role_permissions WHERE tenant_role_id = '00000000-0000-0000-0000-000000000aa2'),
  2::bigint,
  'Administrador has 2 permissions'
);

SELECT throws_ok(
  $$ SELECT public.assign_tenant_role('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000aa2') $$,
  '42501',
  'insufficient_privilege to grant/revoke role',
  'Validador cannot grant Administrador role'
);

-- Test 2: Guard _rbac_assert_can_manage_target
SELECT throws_ok(
  $$ SELECT public.revoke_tenant_role('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000aa2') $$,
  '42501',
  'insufficient_privilege to manage target user',
  'Validador cannot revoke role from Administrador target'
);

-- Test 3: Validador granting Operador
SELECT lives_ok(
  $$ SELECT public.assign_tenant_role('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000aa4') $$,
  'Validador can grant Operador role'
);

-- Test 4: Admin assigns Administrador (creates request)
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000aa","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000aa1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT is(
  (SELECT public.assign_tenant_role('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000aa2') IS NOT NULL),
  true,
  'Admin requests granting Administrador role'
);

-- Test 5: Approving request syncs coarse role
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000ad","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000aa1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.approve_role_change((SELECT id FROM public.role_change_requests WHERE requested_by = '00000000-0000-0000-0000-0000000000aa' AND status = 'PENDING' LIMIT 1)) $$,
  'Second Admin approves Administrador grant'
);

SELECT is(
  (SELECT role FROM public.user_roles WHERE user_id = '00000000-0000-0000-0000-0000000000ac'),
  'TENANT_ADMIN',
  'Target coarse role synced to TENANT_ADMIN'
);

-- Test 6: Revoke Administrador syncs coarse role down
SELECT lives_ok(
  $$ SELECT public.revoke_tenant_role('00000000-0000-0000-0000-0000000000ac', '00000000-0000-0000-0000-000000000aa2') $$,
  'Admin revokes Administrador role'
);

SELECT is(
  (SELECT role FROM public.user_roles WHERE user_id = '00000000-0000-0000-0000-0000000000ac'),
  'OPERATOR',
  'Target coarse role synced back to OPERATOR'
);

-- Test 7: Last-Admin Guard
SELECT lives_ok(
  $$ SELECT public.revoke_tenant_role('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-000000000aa2') $$,
  'Admin 2 revokes Administrador role from Admin 1'
);

SELECT throws_ok(
  $$ SELECT public.revoke_tenant_role('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000aa2') $$,
  'P0001',
  'Cannot demote the last administrator',
  'Last-admin guard prevents demotion'
);

SELECT * FROM finish();
ROLLBACK;
