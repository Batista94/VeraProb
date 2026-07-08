-- =============================================================================
-- pgTAP: Invite Tenant Role Provisioning & Anti-Escalation (20260918000004)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- ── 1. Setup Data ────────────────────────────────────────────────────────────
-- Create Organization
INSERT INTO public.organizations (id, name, legal_name) 
VALUES ('00000000-0000-0000-0000-0000000009d1', 'Test Org', 'Test Org SA');

-- Create Roles
-- Role 1: System Admin
INSERT INTO public.tenant_roles (id, organization_id, name, is_system)
VALUES ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009d1', 'Administrador', true);

-- Role 2: Manager (has users:manage)
INSERT INTO public.tenant_roles (id, organization_id, name, is_system)
VALUES ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-0000000009d1', 'Manager', false);
-- Assume 'users:manage' is in tenant_permissions (already inserted by migration 20260915000001)

-- Role 3: Viewer (no special permissions)
INSERT INTO public.tenant_roles (id, organization_id, name, is_system)
VALUES ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-0000000009d1', 'Viewer', false);

-- Create Users
-- User 1: Manager (has users:manage in JWT)
INSERT INTO auth.users (id, email, email_confirmed_at) 
VALUES ('00000000-0000-0000-0000-000000000901', 'manager@veraprob.test', NOW());

-- User 2: Viewer (no users:manage in JWT)
INSERT INTO auth.users (id, email, email_confirmed_at) 
VALUES ('00000000-0000-0000-0000-000000000902', 'viewer@veraprob.test', NOW());

-- User 3: Invitee
INSERT INTO auth.users (id, email, email_confirmed_at) 
VALUES ('00000000-0000-0000-0000-000000000903', 'invitee@veraprob.test', NOW());

-- ── 2. Test Anti-Escalation (Bug 3) ──────────────────────────────────────────

-- Set caller to Manager (OPERATOR with users:manage)
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000901","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009d1","role":"OPERATOR","permissions":["users:manage"]}}';

-- Manager can invite Viewer
SELECT lives_ok(
  $$ SELECT public.invite_user('invitee1@veraprob.test', 'OPERATOR', 'token1', NOW() + INTERVAL '1 day', '00000000-0000-0000-0000-0000000009f1', '00000000-0000-0000-0000-0000000009e3') $$,
  'Manager can invite with Viewer profile'
);

-- Manager CANNOT invite Admin (coarse role)
SELECT throws_ok(
  $$ SELECT public.invite_user('invitee2@veraprob.test', 'TENANT_ADMIN', 'token2', NOW() + INTERVAL '1 day', '00000000-0000-0000-0000-0000000009f2', NULL) $$,
  'Unauthorized: Only a TENANT_ADMIN can invite another Admin',
  'Manager is blocked from granting TENANT_ADMIN coarse role'
);

-- Manager CANNOT invite Admin (fine-grained profile)
SELECT throws_ok(
  $$ SELECT public.invite_user('invitee2@veraprob.test', 'OPERATOR', 'token2', NOW() + INTERVAL '1 day', '00000000-0000-0000-0000-0000000009f2', '00000000-0000-0000-0000-0000000009e1') $$,
  'Unauthorized: Only a TENANT_ADMIN can invite another Admin',
  'Manager is blocked from granting System Admin profile'
);

-- ── 3. Test Missing Permissions ──────────────────────────────────────────────

-- Set caller to Viewer (OPERATOR without users:manage)
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000902","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009d1","role":"OPERATOR","permissions":[]}}';

SELECT throws_ok(
  $$ SELECT public.invite_user('invitee3@veraprob.test', 'OPERATOR', 'token3', NOW() + INTERVAL '1 day', '00000000-0000-0000-0000-0000000009f3', '00000000-0000-0000-0000-0000000009e3') $$,
  'Unauthorized: TENANT_ADMIN or users:manage permission required to invite users',
  'Viewer cannot invite anyone'
);

-- ── 4. Test Direct Provisioning (Bug 4) ──────────────────────────────────────

-- Set caller to TENANT_ADMIN to properly invite
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000901","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009d1","role":"TENANT_ADMIN","permissions":["*"]}}';

-- Invite User 3 as Viewer
SELECT lives_ok(
  $$ SELECT public.invite_user('invitee@veraprob.test', 'OPERATOR', 'token_accept', NOW() + INTERVAL '1 day', '00000000-0000-0000-0000-0000000009f4', '00000000-0000-0000-0000-0000000009e3') $$,
  'Admin can invite Viewer'
);

-- Verify invitation recorded fine-grained role
SELECT results_eq(
  $$ SELECT tenant_role_id FROM public.invitations WHERE id = '00000000-0000-0000-0000-0000000009f4' $$,
  $$ VALUES ('00000000-0000-0000-0000-0000000009e3'::uuid) $$,
  'Invitation stores tenant_role_id'
);

-- Reset caller to anon to accept invite
SET LOCAL request.jwt.claims = '{"role":"anon"}';

SELECT lives_ok(
  $$ SELECT public.accept_invitation('token_accept', '00000000-0000-0000-0000-000000000903') $$,
  'Accept invitation executes without error'
);

-- Verify user_roles
SELECT results_eq(
  $$ SELECT role FROM public.user_roles WHERE user_id = '00000000-0000-0000-0000-000000000903' $$,
  $$ VALUES ('OPERATOR'::varchar) $$,
  'User is assigned coarse role OPERATOR'
);

-- Verify user_tenant_roles
SELECT results_eq(
  $$ SELECT tenant_role_id FROM public.user_tenant_roles WHERE user_id = '00000000-0000-0000-0000-000000000903' $$,
  $$ VALUES ('00000000-0000-0000-0000-0000000009e3'::uuid) $$,
  'User is directly provisioned with fine-grained Viewer role'
);

SELECT * FROM finish();
ROLLBACK;
