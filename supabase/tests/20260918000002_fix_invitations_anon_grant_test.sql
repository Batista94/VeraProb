BEGIN;

SELECT plan(8);

-- Test that anon has SELECT privilege on invitations

SELECT ok(
  has_table_privilege('anon', 'public.invitations', 'SELECT'),
  'Role anon should have SELECT privilege on public.invitations'
);

-- Test that authenticated has SELECT privilege on invitations
SELECT ok(
  has_table_privilege('authenticated', 'public.invitations', 'SELECT'),
  'Role authenticated should have SELECT privilege on public.invitations'
);

-- Create a mock organization and invitations to test RLS
INSERT INTO public.organizations (id, name, cnpj) VALUES ('b2222222-2222-2222-2222-222222222222', 'Test Org', '12345678000199');

-- Insert a pending invite (active)
INSERT INTO public.invitations (id, organization_id, email, role, token, invited_by, expires_at_utc, revoked_at_utc, accepted_at_utc)
VALUES ('c3333333-3333-3333-3333-333333333333', 'b2222222-2222-2222-2222-222222222222', 'pending@test.com', 'TENANT_OPERATOR', 'token-pending', 'b2222222-2222-2222-2222-222222222222', now() + interval '1 day', null, null);

-- Insert an expired invite
INSERT INTO public.invitations (id, organization_id, email, role, token, invited_by, expires_at_utc, revoked_at_utc, accepted_at_utc)
VALUES ('c4444444-4444-4444-4444-444444444444', 'b2222222-2222-2222-2222-222222222222', 'expired@test.com', 'TENANT_OPERATOR', 'token-expired', 'b2222222-2222-2222-2222-222222222222', now() - interval '1 day', null, null);

-- Insert a revoked invite
INSERT INTO public.invitations (id, organization_id, email, role, token, invited_by, expires_at_utc, revoked_at_utc, accepted_at_utc)
VALUES ('c5555555-5555-5555-5555-555555555555', 'b2222222-2222-2222-2222-222222222222', 'revoked@test.com', 'TENANT_OPERATOR', 'token-revoked', 'b2222222-2222-2222-2222-222222222222', now() + interval '1 day', now(), null);

-- Insert an accepted invite
INSERT INTO public.invitations (id, organization_id, email, role, token, invited_by, expires_at_utc, revoked_at_utc, accepted_at_utc)
VALUES ('c6666666-6666-6666-6666-666666666666', 'b2222222-2222-2222-2222-222222222222', 'accepted@test.com', 'TENANT_OPERATOR', 'token-accepted', 'b2222222-2222-2222-2222-222222222222', now() + interval '1 day', null, now());

-- Switch to anon and test visibility
SET ROLE anon;

SELECT results_eq(
  $$ SELECT token FROM public.invitations WHERE token = 'token-pending' $$,
  $$ VALUES ('token-pending'::text) $$,
  'Role anon can SELECT pending invitations'
);

SELECT is_empty(
  $$ SELECT token FROM public.invitations WHERE token = 'token-expired' $$,
  'Role anon CANNOT see expired invitations'
);

SELECT is_empty(
  $$ SELECT token FROM public.invitations WHERE token = 'token-revoked' $$,
  'Role anon CANNOT see revoked invitations'
);

SELECT is_empty(
  $$ SELECT token FROM public.invitations WHERE token = 'token-accepted' $$,
  'Role anon CANNOT see accepted invitations'
);

-- Reset role and switch to an authenticated user with no tenant admin rights
RESET ROLE;
-- we can mock JWT
SELECT set_config('request.jwt.claims', '{"role":"authenticated","app_metadata":{"org_id":"b2222222-2222-2222-2222-222222222222","role":"TENANT_OPERATOR"}}', true);
SET ROLE authenticated;

SELECT results_eq(
  $$ SELECT token FROM public.invitations WHERE token = 'token-pending' $$,
  $$ VALUES ('token-pending'::text) $$,
  'Role authenticated (operator) can SELECT pending invitations via public policy'
);

SELECT is_empty(
  $$ SELECT token FROM public.invitations WHERE token = 'token-expired' $$,
  'Role authenticated (operator) CANNOT see expired invitations via public policy'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
