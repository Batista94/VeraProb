-- =============================================================================
-- pgTAP: Default Tenant Roles Seed (20260915000002)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ── 1. Create a test organization using the RPC ──────────────────────────────

SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009c9","app_metadata":{"super_admin":true}}';

SELECT public.super_admin_create_organization(
  'Validador Test Org SA',
  'Validador Test Org',
  '99999999000199',
  'America/Sao_Paulo',
  'BRL',
  'enterprise',
  1000,
  50,
  '00000000-0000-0000-0000-0000000009c9'::uuid
);

CREATE TEMP TABLE t_test_org AS
SELECT id FROM public.organizations WHERE legal_name = 'Validador Test Org SA' LIMIT 1;

-- ── 2. Assert default profiles were created ──────────────────────────────────

SELECT results_eq(
  $$ SELECT name FROM public.tenant_roles WHERE organization_id = (SELECT id FROM t_test_org) ORDER BY name $$,
  $$ VALUES ('Administrador'), ('Auditor'), ('Operador'), ('Validador') $$,
  'The 4 default profiles (Administrador, Auditor, Operador, Validador) are created for new orgs'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.tenant_roles WHERE organization_id = (SELECT id FROM t_test_org) AND NOT is_system $$,
  $$ VALUES (0) $$,
  'All 4 default profiles are marked as is_system = true'
);

-- ── 3. Assert Validador profile permissions ──────────────────────────────────

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
      ('telemetry:read'),
      ('users:manage')
  $$,
  'Validador profile has operational/approval access but NO roles:manage or org:manage'
);

-- ── 4. Assert Administrador profile permissions ──────────────────────────────

SELECT results_eq(
  $$
    SELECT count(*)::int
    FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Administrador'
  $$,
  $$ SELECT count(*)::int FROM public.tenant_permissions $$,
  'Administrador profile has ALL available permissions'
);

-- ── 5. Assert Auditor profile permissions ────────────────────────────────────

SELECT results_eq(
  $$
    SELECT trp.permission_key
    FROM public.tenant_role_permissions trp
    JOIN public.tenant_roles tr ON tr.id = trp.tenant_role_id
    WHERE tr.organization_id = (SELECT id FROM t_test_org)
      AND tr.name = 'Auditor'
    ORDER BY trp.permission_key
  $$,
  $$
    VALUES 
      ('cadastros:read'),
      ('financial:export'),
      ('financial:read'),
      ('roles:read'),
      ('sla:read'),
      ('telemetry:read')
  $$,
  'Auditor profile has only read and export permissions (no mutations or SLA approvals)'
);

-- ── 6. Assert Operador profile permissions ───────────────────────────────────

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
      ('contracts:write'),
      ('sla:read'),
      ('telemetry:read')
  $$,
  'Operador profile has operational mutations but NO financial, role, or user access'
);

-- ── 7. Retroactive Seed Validation (Helper Function) ─────────────────────────

-- Insert an org bypassing the RPC
INSERT INTO public.organizations (id, name, legal_name) 
VALUES ('00000000-0000-0000-0000-0000000009d1', 'Retro Org', 'Retro Org SA');

-- Call the retroactive seeder explicitly (as the migration would have done)
SELECT public._seed_default_tenant_roles('00000000-0000-0000-0000-0000000009d1'::uuid);

SELECT is(
  (SELECT count(*)::int FROM public.tenant_roles WHERE organization_id = '00000000-0000-0000-0000-0000000009d1'::uuid),
  4,
  'Retroactive seeding helper ensures old organizations get the 4 default profiles'
);

SELECT * FROM finish();
ROLLBACK;
