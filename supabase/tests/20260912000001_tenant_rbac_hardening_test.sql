-- =============================================================================
-- pgTAP: Tenant RBAC hardening (Pilar 1 post-audit F1-F4) — 20260912000001
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Fixtures (superuser, pre-RLS) ────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009f1', 'RBAC Hardening Org', 'RBAC Hardening SA',
   '0000000000ha1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rbac-hard@test.com', 'EXT_RBAC_HARD', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Role carrying roles:manage — backs the approver's live-check row (F4).
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-0000000009d1', '00000000-0000-0000-0000-0000000009f1',
   'Manage Only', false),
  -- Role holding a sensitive perm — subject of the GRANT_ROLE request (F2).
  ('00000000-0000-0000-0000-0000000009d2', '00000000-0000-0000-0000-0000000009f1',
   'Financial Export', false),
  -- Plain target role for the UPDATE request (F2).
  ('00000000-0000-0000-0000-0000000009d3', '00000000-0000-0000-0000-0000000009f1',
   'Update Target', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-0000000009d1', 'roles:manage'),
  ('00000000-0000-0000-0000-0000000009d2', 'financial:export')
ON CONFLICT DO NOTHING;

-- Approver 09aa: coarse claim with roles:manage AND a live grant → passes F4.
INSERT INTO public.user_tenant_roles (user_id, tenant_role_id, organization_id) VALUES
  ('00000000-0000-0000-0000-0000000009aa', '00000000-0000-0000-0000-0000000009d1',
   '00000000-0000-0000-0000-0000000009f1')
ON CONFLICT (user_id, tenant_role_id) DO NOTHING;

-- Pending requests (state under test; requested_by = 09a9 for all).
INSERT INTO public.role_change_requests
  (id, organization_id, request_type, payload, requested_by, status, created_at)
VALUES
  ('00000000-0000-0000-0000-0000000009e0', '00000000-0000-0000-0000-0000000009f1',
   'UPDATE_ROLE_PERMISSIONS',
   '{"role_id":"00000000-0000-0000-0000-0000000009d3","perm_grants":[{"key":"financial:export"}]}'::jsonb,
   '00000000-0000-0000-0000-0000000009a9', 'PENDING', NOW()),
  ('00000000-0000-0000-0000-0000000009e3', '00000000-0000-0000-0000-0000000009f1',
   'GRANT_ROLE',
   '{"role_id":"00000000-0000-0000-0000-0000000009d2","target_user":"00000000-0000-0000-0000-0000000009c9","valid_until":null}'::jsonb,
   '00000000-0000-0000-0000-0000000009a9', 'PENDING', NOW()),
  ('00000000-0000-0000-0000-0000000009e1', '00000000-0000-0000-0000-0000000009f1',
   'UPDATE_ROLE_PERMISSIONS',
   '{"role_id":"00000000-0000-0000-0000-0000000009d3","perm_grants":[{"key":"telemetry:read"}]}'::jsonb,
   '00000000-0000-0000-0000-0000000009a9', 'PENDING', NOW() - INTERVAL '73 hours'),
  ('00000000-0000-0000-0000-0000000009e2', '00000000-0000-0000-0000-0000000009f1',
   'UPDATE_ROLE_PERMISSIONS',
   '{"role_id":"00000000-0000-0000-0000-0000000009d3","perm_grants":[{"key":"telemetry:read"}]}'::jsonb,
   '00000000-0000-0000-0000-0000000009a9', 'PENDING', NOW())
ON CONFLICT (id) DO NOTHING;

-- ── F1: service_role EXECUTE on all 7 hardened functions ─────────────────────
SELECT ok(has_function_privilege('service_role',
  'public.create_tenant_role(text,text,jsonb)', 'EXECUTE'),
  'F1: service_role can EXECUTE create_tenant_role');
SELECT ok(has_function_privilege('service_role',
  'public.update_tenant_role_permissions(uuid,jsonb)', 'EXECUTE'),
  'F1: service_role can EXECUTE update_tenant_role_permissions');
SELECT ok(has_function_privilege('service_role',
  'public.assign_tenant_role(uuid,uuid,timestamptz)', 'EXECUTE'),
  'F1: service_role can EXECUTE assign_tenant_role');
SELECT ok(has_function_privilege('service_role',
  'public.revoke_tenant_role(uuid,uuid)', 'EXECUTE'),
  'F1: service_role can EXECUTE revoke_tenant_role');
SELECT ok(has_function_privilege('service_role',
  'public.approve_role_change(uuid)', 'EXECUTE'),
  'F1: service_role can EXECUTE approve_role_change');
SELECT ok(has_function_privilege('service_role',
  'public.reject_role_change(uuid)', 'EXECUTE'),
  'F1: service_role can EXECUTE reject_role_change');
SELECT ok(has_function_privilege('service_role',
  'public.revoke_user_sessions(uuid)', 'EXECUTE'),
  'F1: service_role can EXECUTE revoke_user_sessions');

SET LOCAL ROLE authenticated;

-- ── F4: revoked roles:manage rejected inside the RBAC RPC (no live row) ───────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009ac","organization_id":"00000000-0000-0000-0000-0000000009f1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f1","role":"OPERATOR","permissions":["roles:manage"]}}';

SELECT throws_ok(
  $$ SELECT public.create_tenant_role('F4 Stale', NULL, '[]'::jsonb) $$,
  '42501',
  'Permission revoked or insufficient',
  'F4: stale roles:manage claim with no active grant is denied (live-check)');

-- ── F4: wildcard holder with no grant row bypasses the live-check ────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a9","organization_id":"00000000-0000-0000-0000-0000000009f1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.create_tenant_role('F4 Wildcard', NULL, '[]'::jsonb) $$,
  'F4: wildcard admin bypasses live-check with no grant row');

-- ── F2: approver bounded by own ceiling on UPDATE approval ───────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009aa","organization_id":"00000000-0000-0000-0000-0000000009f1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f1","role":"OPERATOR","permissions":["roles:manage"]}}';

SELECT throws_ok(
  $$ SELECT public.approve_role_change('00000000-0000-0000-0000-0000000009e0') $$,
  'P0001',
  'PrivilegeEscalation: cannot grant unheld permission',
  'F2: approver holding only roles:manage cannot approve a financial:export grant');

-- ── F2: wildcard approver applies the same request ───────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009ab","organization_id":"00000000-0000-0000-0000-0000000009f1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.approve_role_change('00000000-0000-0000-0000-0000000009e0') $$,
  'F2: wildcard approver applies the UPDATE request');

SELECT is(
  (SELECT status FROM public.role_change_requests
    WHERE id = '00000000-0000-0000-0000-0000000009e0'),
  'APPROVED',
  'F2: request transitions to APPROVED after wildcard approval');

-- ── F2: approver ceiling enforced on GRANT_ROLE approval ─────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009aa","organization_id":"00000000-0000-0000-0000-0000000009f1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f1","role":"OPERATOR","permissions":["roles:manage"]}}';

SELECT throws_ok(
  $$ SELECT public.approve_role_change('00000000-0000-0000-0000-0000000009e3') $$,
  'P0001',
  'PrivilegeEscalation: cannot grant unheld permission',
  'F2: approver cannot route a role carrying financial:export they do not hold');

-- ── F3: reject of an expired request raises instead of stamping REJECTED ──────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009ab","organization_id":"00000000-0000-0000-0000-0000000009f1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT throws_ok(
  $$ SELECT public.reject_role_change('00000000-0000-0000-0000-0000000009e1') $$,
  'P0001',
  'Request has expired',
  'F3: rejecting a >72h request raises expiry instead of REJECTED');

-- ── F3: reject of a fresh request stamps REJECTED ────────────────────────────
SELECT lives_ok(
  $$ SELECT public.reject_role_change('00000000-0000-0000-0000-0000000009e2') $$,
  'F3: fresh pending request is rejected');

SELECT is(
  (SELECT status FROM public.role_change_requests
    WHERE id = '00000000-0000-0000-0000-0000000009e2'),
  'REJECTED',
  'F3: fresh request transitions to REJECTED');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
