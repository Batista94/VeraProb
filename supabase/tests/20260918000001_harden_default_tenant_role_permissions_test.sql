-- =============================================================================
-- pgTAP: Harden Default Tenant Roles Seed (20260918000001)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ── 1. Create a test organization using the RPC ──────────────────────────────

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009c9","app_metadata":{"super_admin":true}}';

SELECT public.super_admin_create_organization(
  'Hardened Test Org SA',
  'Hardened Test Org',
  '99999999000198',
  'America/Sao_Paulo',
  'BRL',
  'enterprise',
  1000,
  50,
  '00000000-0000-0000-0000-0000000009c9'::uuid
);

CREATE TEMP TABLE t_test_org AS
SELECT id FROM public.organizations WHERE legal_name = 'Hardened Test Org SA' LIMIT 1;

-- ── 2. Assert Validador profile permissions (Hardened) ───────────────────────

SELECT results_eq(
  $$
    SELECT trp.permission_key
    FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Validador'
    ORDER BY trp.permission_key
  $$,
  $$
    VALUES 
      ('cadastros:read'),
      ('cadastros:write'),
      ('contracts:read'),
      ('contracts:write'),
      ('financial:export'),
      ('financial:read'),
      ('roles:read'),
      ('sla:approve'),
      ('sla:read'),
      ('telemetry:read')
  $$,
  'Validador profile has exactly 10 permissions. users:manage is REMOVED (SoD)'
);

SELECT is_empty(
  $$
    SELECT 1 FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Validador'
      AND trp.permission_key = 'users:manage'
  $$,
  'Validador DOES NOT have users:manage'
);

-- ── 3. Assert Operador profile permissions (Hardened) ────────────────────────

SELECT results_eq(
  $$
    SELECT trp.permission_key
    FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Operador'
    ORDER BY trp.permission_key
  $$,
  $$
    VALUES 
      ('cadastros:read'),
      ('cadastros:write'),
      ('contracts:read'),
      ('sla:read'),
      ('telemetry:read')
  $$,
  'Operador profile has exactly 5 permissions. contracts:write is REMOVED (PoLP)'
);

SELECT is_empty(
  $$
    SELECT 1 FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Operador'
      AND trp.permission_key = 'contracts:write'
  $$,
  'Operador DOES NOT have contracts:write'
);

-- ── 4. Assert Auditor profile permissions (Regression) ───────────────────────

SELECT results_eq(
  $$
    SELECT count(*)::int
    FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Auditor'
  $$,
  $$ VALUES (6) $$,
  'Auditor profile remains unchanged with exactly 6 permissions'
);

-- ── 5. Assert Administrador profile permissions (Regression) ─────────────────

SELECT results_eq(
  $$
    SELECT count(*)::int
    FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Administrador'
  $$,
  $$ SELECT count(*)::int FROM public.tenant_permissions $$,
  'Administrador profile remains unchanged with ALL permissions'
);

-- ── 6. Retroactive Seed Validation (Helper Function) ─────────────────────────

-- Insert an org bypassing the RPC
INSERT INTO public.organizations (id, name, legal_name) 
VALUES ('00000000-0000-0000-0000-0000000009d2', 'Retro Org 2', 'Retro Org SA 2');

-- Call the retroactive seeder explicitly
SELECT public._seed_default_tenant_roles('00000000-0000-0000-0000-0000000009d2'::uuid);

SELECT is_empty(
  $$
    SELECT 1 FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = '00000000-0000-0000-0000-0000000009d2'::uuid
      AND tr.name = 'Validador'
      AND trp.permission_key = 'users:manage'
  $$,
  'Retroactive seeding helper applies the hardened matrix without users:manage'
);

SELECT * FROM finish();
ROLLBACK;
