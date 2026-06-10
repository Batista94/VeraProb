-- =============================================================================
-- Test plan: 20260811000001_harden_identity_trust_roots
--
-- Asserts that the identity/tenant trust-root tables (user_roles, organizations)
-- are read-only to `authenticated` at the GRANT layer, so the organization_id
-- claim source cannot be written by a client role under any future RLS policy.
-- `super_admin_users` must stay client-inaccessible. service_role unaffected.
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- (1) user_roles — claim source: authenticated read-only (no write primitive)
SELECT ok(    has_table_privilege('authenticated', 'public.user_roles', 'SELECT'),
  'authenticated retains SELECT on user_roles');
SELECT ok(NOT has_table_privilege('authenticated', 'public.user_roles', 'INSERT'),
  'authenticated cannot INSERT user_roles (no self-elevation primitive)');
SELECT ok(NOT has_table_privilege('authenticated', 'public.user_roles', 'UPDATE'),
  'authenticated cannot UPDATE user_roles');
SELECT ok(NOT has_table_privilege('authenticated', 'public.user_roles', 'DELETE'),
  'authenticated cannot DELETE user_roles');
SELECT ok(NOT has_table_privilege('anon', 'public.user_roles', 'SELECT'),
  'anon has no access to user_roles');

-- (2) organizations — tenant root: authenticated read-only
SELECT ok(    has_table_privilege('authenticated', 'public.organizations', 'SELECT'),
  'authenticated retains SELECT on organizations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'INSERT'),
  'authenticated cannot INSERT organizations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'UPDATE'),
  'authenticated cannot UPDATE organizations');
SELECT ok(NOT has_table_privilege('authenticated', 'public.organizations', 'DELETE'),
  'authenticated cannot DELETE organizations');

-- (3) super_admin_users — god-mode root stays client-inaccessible
SELECT ok(NOT has_table_privilege('authenticated', 'public.super_admin_users', 'SELECT'),
  'authenticated has no access to super_admin_users');
SELECT ok(NOT has_table_privilege('anon', 'public.super_admin_users', 'SELECT'),
  'anon has no access to super_admin_users');

-- (4) service_role (trusted backend / SECURITY DEFINER definer) unaffected
SELECT ok(    has_table_privilege('service_role', 'public.user_roles', 'INSERT'),
  'service_role retains write on user_roles');

SELECT * FROM finish();
ROLLBACK;
