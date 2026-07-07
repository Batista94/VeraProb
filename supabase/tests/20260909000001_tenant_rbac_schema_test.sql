-- =============================================================================
-- pgTAP: Tenant RBAC schema (Pilar 1.1) — migration 20260909000001
-- Global Catalog RLS Pattern (SSOT: dispute_reason_codes).
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

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

INSERT INTO public.tenant_permissions
  (key, module, action, label_pt, organization_id)
VALUES
  ('orgb:private', 'custom', 'read', 'Permissão privada Org B',
   '00000000-0000-0000-0000-0000000009b1')
ON CONFLICT (key) DO NOTHING;

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_table('public', 'tenant_permissions', 'tenant_permissions exists');
SELECT has_table('public', 'tenant_roles', 'tenant_roles exists');
SELECT has_table('public', 'role_change_requests', 'role_change_requests exists');

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.tenant_permissions'::regclass),
  'RLS enabled on tenant_permissions (INV-2)');

-- ── Global catalog seed ────────────────────────────────────────────────────────
SELECT ok(
  (SELECT count(*)::int FROM public.tenant_permissions WHERE organization_id IS NULL) >= 10,
  'global permission dictionary seeded (organization_id IS NULL)');

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.tenant_permissions
     WHERE key = 'roles:manage' AND is_sensitive AND organization_id IS NULL
  ),
  'roles:manage marked sensitive in global catalog');

-- ── Grants ───────────────────────────────────────────────────────────────────
SELECT ok(
  has_table_privilege('authenticated', 'public.tenant_permissions', 'SELECT'),
  'authenticated may SELECT tenant_permissions');

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.tenant_roles', 'INSERT'),
  'authenticated cannot INSERT tenant_roles directly');

-- ── RLS: Global Catalog Pattern (authenticated, Org A) ───────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009a2","organization_id":"00000000-0000-0000-0000-0000000009a1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009a1","role":"OPERATOR"}}';

SELECT ok(
  (SELECT count(*)::int FROM public.tenant_permissions WHERE organization_id IS NULL) >= 10,
  'authenticated tenant sees global catalog rows');

SELECT is(
  (SELECT count(*)::int FROM public.tenant_permissions WHERE key = 'orgb:private'),
  0,
  'Org A cannot see Org B private permission key (INV-22)');

SELECT throws_ok(
  $$ INSERT INTO public.tenant_permissions (key, module, action, label_pt)
     VALUES ('client:made', 'custom', 'read', 'x') $$,
  '42501', NULL,
  'authenticated cannot INSERT permission keys (no INSERT policy)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
