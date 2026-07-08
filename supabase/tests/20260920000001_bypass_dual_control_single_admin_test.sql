BEGIN;
SELECT plan(11);

-- ── Setup ─────────────────────────────────────────────────────────────────────
-- Organization with multiple admins
INSERT INTO public.organizations (id, name, cnpj)
VALUES ('00000000-0000-0000-0000-0000000009c1', 'Multi Admin Org', '00.000.000/0000-00');

-- Organization with a single admin
INSERT INTO public.organizations (id, name, cnpj)
VALUES ('00000000-0000-0000-0000-0000000009c2', 'Single Admin Org', '11.111.111/1111-11');

-- Users
INSERT INTO auth.users (id, email) VALUES
('00000000-0000-0000-0000-000000000aa1', 'admin1@multi.com'),
('00000000-0000-0000-0000-000000000aa2', 'admin2@multi.com'),
('00000000-0000-0000-0000-000000000bb1', 'admin1@single.com'),
('00000000-0000-0000-0000-000000000bb2', 'operator1@single.com');


-- Roles (Multi Admin)
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
('00000000-0000-0000-0000-000000000aa1', '00000000-0000-0000-0000-0000000009c1', 'TENANT_ADMIN'),
('00000000-0000-0000-0000-000000000aa2', '00000000-0000-0000-0000-0000000009c1', 'TENANT_ADMIN');

-- Roles (Single Admin)
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
('00000000-0000-0000-0000-000000000bb1', '00000000-0000-0000-0000-0000000009c2', 'TENANT_ADMIN'),
('00000000-0000-0000-0000-000000000bb2', '00000000-0000-0000-0000-0000000009c2', 'OPERATOR');

-- Normal Tenant Role to be assigned
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
('00000000-0000-0000-0000-000000000ff1', '00000000-0000-0000-0000-0000000009c2', 'Sensitive Assignable', false);
INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
('00000000-0000-0000-0000-000000000ff1', 'roles:manage');

-- ── Test 1: Count Approvers ───────────────────────────────────────────────────
SELECT is(
  public._rbac_count_approvers('00000000-0000-0000-0000-0000000009c1'::uuid),
  2,
  'Multi admin org has 2 approvers'
);

SELECT is(
  public._rbac_count_approvers('00000000-0000-0000-0000-0000000009c2'::uuid),
  1,
  'Single admin org has 1 approver'
);

-- ── Test 2: Multi Admin Org - Must go to role_change_requests ───────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000aa1","organization_id":"00000000-0000-0000-0000-0000000009c1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009c1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.create_tenant_role(
       'Sensitive Role',
       'test',
       '[{"key":"roles:manage"}]'::jsonb
     ) $$,
  'create_tenant_role in multi-admin org executes without error'
);

SELECT is(
  (SELECT status FROM public.role_change_requests
    WHERE request_type = 'CREATE_ROLE'
      AND organization_id = '00000000-0000-0000-0000-0000000009c1'
    ORDER BY created_at DESC LIMIT 1),
  'PENDING',
  'Multi-admin sensitive role creation generates PENDING request'
);

SELECT is(
  (SELECT COUNT(*) FROM public.tenant_roles WHERE name = 'Sensitive Role' AND organization_id = '00000000-0000-0000-0000-0000000009c1'),
  0::bigint,
  'Multi-admin sensitive role is NOT created immediately'
);

-- ── Test 3: Single Admin Org - Bypass role_change_requests ─────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000bb1","organization_id":"00000000-0000-0000-0000-0000000009c2","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009c2","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.create_tenant_role(
       'Bypass Role',
       'test single admin bypass',
       '[{"key":"roles:manage"}]'::jsonb
     ) $$,
  'create_tenant_role in single-admin org executes without error'
);

SELECT is(
  (SELECT COUNT(*) FROM public.role_change_requests
    WHERE request_type = 'CREATE_ROLE'
      AND payload->>'name' = 'Bypass Role'
      AND organization_id = '00000000-0000-0000-0000-0000000009c2'),
  0::bigint,
  'Single-admin sensitive role creation does NOT generate a request'
);

SELECT is(
  (SELECT COUNT(*) FROM public.tenant_roles WHERE name = 'Bypass Role' AND organization_id = '00000000-0000-0000-0000-0000000009c2'),
  1::bigint,
  'Single-admin sensitive role is created immediately'
);

-- Assign Role Test
SELECT lives_ok(
  $$ SELECT public.assign_tenant_role('00000000-0000-0000-0000-000000000bb2', '00000000-0000-0000-0000-000000000ff1', NULL::timestamptz) $$,
  'assign_tenant_role in single-admin org executes without error'
);

SELECT is(
  (SELECT COUNT(*) FROM public.role_change_requests
    WHERE request_type = 'GRANT_ROLE'
      AND organization_id = '00000000-0000-0000-0000-0000000009c2'),
  0::bigint,
  'Single-admin sensitive role assignment does NOT generate a request'
);

SELECT is(
  (SELECT COUNT(*) FROM public.user_tenant_roles
    WHERE user_id = '00000000-0000-0000-0000-000000000bb2'
      AND tenant_role_id = '00000000-0000-0000-0000-000000000ff1'
      AND revoked_at IS NULL),
  1::bigint,
  'Single-admin sensitive role assignment is applied immediately'
);

SELECT * FROM finish();
ROLLBACK;
