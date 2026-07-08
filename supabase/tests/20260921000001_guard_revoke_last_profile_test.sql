-- =============================================================================
-- pgTAP: Last-profile guard on revoke_tenant_role
-- Migration: 20260921000001_guard_revoke_last_profile
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

-- Setup
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-000000002100',
  'Last Profile Org', 'LP Org SA', '000000000002100',
  'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
  'lp@test.com', 'EXT_LP', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-000000002111'),
  ('00000000-0000-0000-0000-000000002112'),
  ('00000000-0000-0000-0000-000000002113')
ON CONFLICT DO NOTHING;

-- Admin (caller)
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
  ('00000000-0000-0000-0000-000000002111', '00000000-0000-0000-0000-000000002100', 'TENANT_ADMIN'),
  ('00000000-0000-0000-0000-000000002112', '00000000-0000-0000-0000-000000002100', 'TENANT_ADMIN')
ON CONFLICT DO NOTHING;

-- Two roles: one with financial:read (non-sensitive), one with sla:approve (sensitive)
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-000000002190', '00000000-0000-0000-0000-000000002100', 'LP-Basic', false),
  ('00000000-0000-0000-0000-000000002191', '00000000-0000-0000-0000-000000002100', 'LP-Sensitive', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-000000002190', 'financial:read'),
  ('00000000-0000-0000-0000-000000002191', 'sla:approve')
ON CONFLICT DO NOTHING;

-- user-2 has TWO active roles (multi-role)
INSERT INTO public.user_tenant_roles (user_id, tenant_role_id, organization_id, granted_by) VALUES
  ('00000000-0000-0000-0000-000000002112', '00000000-0000-0000-0000-000000002190', '00000000-0000-0000-0000-000000002100', '00000000-0000-0000-0000-000000002111'),
  ('00000000-0000-0000-0000-000000002112', '00000000-0000-0000-0000-000000002191', '00000000-0000-0000-0000-000000002100', '00000000-0000-0000-0000-000000002111')
ON CONFLICT DO NOTHING;

-- user-3 has ONE active role (single-role, last profile)
INSERT INTO public.user_tenant_roles (user_id, tenant_role_id, organization_id, granted_by) VALUES
  ('00000000-0000-0000-0000-000000002113', '00000000-0000-0000-0000-000000002190', '00000000-0000-0000-0000-000000002100', '00000000-0000-0000-0000-000000002111')
ON CONFLICT DO NOTHING;

-- ── Act as admin ─────────────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000002111","organization_id":"00000000-0000-0000-0000-000000002100","app_metadata":{"org_id":"00000000-0000-0000-0000-000000002100","role":"TENANT_ADMIN","permissions":["*"]}}';

-- Test 1: revoke one of two roles succeeds (user still has 1 remaining)
SELECT lives_ok(
  $$ SELECT public.revoke_tenant_role(
       '00000000-0000-0000-0000-000000002112',
       '00000000-0000-0000-0000-000000002191'
     ) $$,
  'revoking one of two roles succeeds -- user keeps 1 active profile'
);

-- Test 2: now user-2 has 1 role; revoking the last one must fail (LastProfileGuard)
SELECT throws_ok(
  $$ SELECT public.revoke_tenant_role(
       '00000000-0000-0000-0000-000000002112',
       '00000000-0000-0000-0000-000000002190'
     ) $$,
  'P0001',
  'LastProfileGuard: cannot remove the last active profile from a member',
  'revoking last profile raises LastProfileGuard'
);

-- Test 3: user-2 still has the role (rollback confirmed)
SELECT is(
  (SELECT COUNT(*)::int FROM public.user_tenant_roles
    WHERE user_id = '00000000-0000-0000-0000-000000002112'
      AND tenant_role_id = '00000000-0000-0000-0000-000000002190'
      AND revoked_at IS NULL),
  1,
  'last-profile soft-revoke was rolled back atomically'
);

-- Test 4: user-3 (single-role) -- revocation must fail
SELECT throws_ok(
  $$ SELECT public.revoke_tenant_role(
       '00000000-0000-0000-0000-000000002113',
       '00000000-0000-0000-0000-000000002190'
     ) $$,
  'P0001',
  'LastProfileGuard: cannot remove the last active profile from a member',
  'user with only one role cannot have it revoked'
);

-- Test 5: no ROLE_REVOKED audit entry for blocked revocations
-- (read system_audit_log as superuser — authenticated lacks SELECT on it)
RESET ROLE;
SELECT is(
  (SELECT COUNT(*)::int FROM public.system_audit_log
    WHERE event_type = 'ROLE_REVOKED'
      AND payload->>'target_user' = '00000000-0000-0000-0000-000000002113'),
  0,
  'no audit entry written for blocked last-profile revocation'
);

SELECT * FROM finish();
ROLLBACK;