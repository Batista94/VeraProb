-- =============================================================================
-- pgTAP: Tenant RBAC mutation RPCs (Pilar 1.4) — migration 20260909000004
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009a1', 'RBAC Org A', 'RBAC Org A SA', '000000000009a1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rbac-a@test.com', 'EXT_RBAC_A', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-0000000009b1', 'RBAC Org B', 'RBAC Org B SA', '000000000009b1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'rbac-b@test.com', 'EXT_RBAC_B', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_roles (id, organization_id, name, description, is_system) VALUES
  ('00000000-0000-0000-0000-0000000009c3', '00000000-0000-0000-0000-0000000009b1',
   'Org B Role', 'Cross-tenant bait', false),
  ('00000000-0000-0000-0000-0000000009c5', '00000000-0000-0000-0000-0000000009a1',
   'Org A Manage', 'Backs live-check for roles:manage', false)
ON CONFLICT (id) DO NOTHING;

-- Live grant backing the escalation caller's roles:manage claim (F4 live-check).
INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-0000000009c5', 'roles:manage')
ON CONFLICT DO NOTHING;

INSERT INTO public.user_tenant_roles (user_id, tenant_role_id, organization_id) VALUES
  ('00000000-0000-0000-0000-0000000009a2', '00000000-0000-0000-0000-0000000009c5',
   '00000000-0000-0000-0000-0000000009a1')
ON CONFLICT (user_id, tenant_role_id) DO NOTHING;

SELECT has_function('public', 'create_tenant_role', ARRAY['text', 'text', 'jsonb']);
SELECT has_function('public', 'assign_tenant_role', ARRAY['uuid', 'uuid', 'timestamp with time zone']);

-- ── Silent deny / INV-26 ─────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT is(
  (SELECT count(*)::int FROM public.tenant_roles
    WHERE organization_id = '00000000-0000-0000-0000-0000000009b1'),
  0,
  'cross-tenant SELECT on tenant_roles returns 0 rows (INV-26 silent deny)');

SELECT throws_ok(
  $$ SELECT public.assign_tenant_role(
       '00000000-0000-0000-0000-0000000009a2',
       '00000000-0000-0000-0000-0000000009c3',
       NULL
     ) $$,
  '42501',
  'Not found.',
  'assign_tenant_role on foreign-org role raises insufficient_privilege');

-- ── Privilege escalation block ─────────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a2","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"OPERATOR","permissions":["financial:read","telemetry:read","roles:manage"]}}';

SELECT throws_ok(
  $$ SELECT public.create_tenant_role(
       'Escalation Bait',
       'must fail',
       '[{"key":"sla:approve"}]'::jsonb
     ) $$,
  'P0001',
  'PrivilegeEscalation: cannot grant unheld permission',
  'subset guard blocks privilege escalation');

SELECT throws_ok(
  $$ SELECT public.create_tenant_role(
       'Bad Key',
       'invalid dictionary key',
       '[{"key":"nonexistent:perm"}]'::jsonb
     ) $$,
  'P0001',
  NULL,
  'unknown permission key rejected with IntegrityException');

-- ── Four-eyes queue ───────────────────────────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a9","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.create_tenant_role(
       'Sensitive Profile',
       'requires second admin',
       '[{"key":"financial:export"}]'::jsonb
     ) $$,
  'sensitive create_tenant_role defers to four-eyes queue');

SELECT is(
  (SELECT status FROM public.role_change_requests
    WHERE request_type = 'CREATE_ROLE'
      AND organization_id = '00000000-0000-0000-0000-0000000009a1'
    ORDER BY created_at DESC LIMIT 1),
  'PENDING',
  'sensitive role creation enqueues PENDING request');

SELECT throws_ok(
  $$ SELECT public.approve_role_change(
       (SELECT id FROM public.role_change_requests
         WHERE request_type = 'CREATE_ROLE'
           AND organization_id = '00000000-0000-0000-0000-0000000009a1'
         ORDER BY created_at DESC LIMIT 1)
     ) $$,
  'P0001',
  'Self-approval is not permitted',
  'requester cannot self-approve (CHECK + RPC guard)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
