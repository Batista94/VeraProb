-- =============================================================================
-- pgTAP: current_perms_v() permissions version source (Pilar 2 ADJ-1)
-- Migration: 20260911000001_tenant_rbac_perms_version
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ── Fixture ───────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000000c001', 'PermsV Org A', 'PermsV Org A SA', '0000000000c001',
   'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
   'permsv-a@test.com', 'EXT_PERMSV_A', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- user_roles has FK to auth.users — bypass with replica role (established pattern).
SET LOCAL session_replication_role = replica;
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
  ('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-00000000c001', 'OPERATOR')
ON CONFLICT (user_id) DO UPDATE
  SET organization_id = EXCLUDED.organization_id, role = EXCLUDED.role;
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.tenant_roles (id, organization_id, name, description, is_system) VALUES
  ('00000000-0000-0000-0000-00000000c0b1', '00000000-0000-0000-0000-00000000c001',
   'PermsV Role', 'Deterministic updated_at fixture', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key, scope) VALUES
  ('00000000-0000-0000-0000-00000000c0b1', 'financial:read', NULL)
ON CONFLICT DO NOTHING;

-- Pin updated_at to a fixed instant T1 (the trigger already bumped it on the
-- permission INSERT above; override for a deterministic epoch assertion).
UPDATE public.tenant_roles
   SET updated_at = TIMESTAMPTZ '2026-01-01 00:00:00+00'
 WHERE id = '00000000-0000-0000-0000-00000000c0b1';

INSERT INTO public.user_tenant_roles (
  user_id, tenant_role_id, organization_id, valid_from, valid_until, revoked_at
) VALUES
  ('00000000-0000-0000-0000-00000000c0a1', '00000000-0000-0000-0000-00000000c0b1',
   '00000000-0000-0000-0000-00000000c001', NOW() - INTERVAL '1 day', NULL, NULL)
ON CONFLICT (user_id, tenant_role_id) DO UPDATE
  SET revoked_at = NULL, valid_until = NULL, valid_from = NOW() - INTERVAL '1 day';

-- ── 1. Function exists ────────────────────────────────────────────────────────
SELECT has_function(
  'public', 'current_perms_v', ARRAY[]::text[],
  'current_perms_v() is registered');

-- ── 2. Wildcard admin short-circuits to 0 (parity with hook) ──────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c0a9","organization_id":"00000000-0000-0000-0000-00000000c001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c001","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT is(
  public.current_perms_v(),
  0::bigint,
  'wildcard holder (TENANT_ADMIN) returns 0 — parity with hook');

-- ── 3. Baseline: epoch of the single active role updated_at (T1) ──────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c0a1","organization_id":"00000000-0000-0000-0000-00000000c001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c001","role":"OPERATOR","permissions":["financial:read"]}}';

SELECT is(
  public.current_perms_v(),
  EXTRACT(EPOCH FROM TIMESTAMPTZ '2026-01-01 00:00:00+00')::bigint,
  'version equals epoch of active role updated_at');

-- ── 4. Parity with the JWT hook's perms_v for the same operator ───────────────
SELECT is(
  public.current_perms_v(),
  (
    public.custom_access_token_hook(jsonb_build_object(
      'user_id', '00000000-0000-0000-0000-00000000c0a1',
      'claims', jsonb_build_object('app_metadata', '{}'::jsonb)
    )) -> 'claims' -> 'app_metadata' -> 'perms_v'
  )::text::bigint,
  'current_perms_v() matches the hook-injected perms_v (single SSOT)');

-- ── 5. Permission-matrix edit bumps the version (T2 <> T1) ────────────────────
RESET ROLE;
UPDATE public.tenant_roles
   SET updated_at = TIMESTAMPTZ '2026-02-01 00:00:00+00'
 WHERE id = '00000000-0000-0000-0000-00000000c0b1';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c0a1","organization_id":"00000000-0000-0000-0000-00000000c001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c001","role":"OPERATOR","permissions":["financial:read"]}}';

SELECT is(
  public.current_perms_v(),
  EXTRACT(EPOCH FROM TIMESTAMPTZ '2026-02-01 00:00:00+00')::bigint,
  'matrix edit (updated_at bump) changes the version');

-- ── 6. Revoked grant excludes the role → version collapses to 0 ───────────────
RESET ROLE;
UPDATE public.user_tenant_roles
   SET revoked_at = NOW()
 WHERE user_id        = '00000000-0000-0000-0000-00000000c0a1'
   AND tenant_role_id = '00000000-0000-0000-0000-00000000c0b1';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c0a1","organization_id":"00000000-0000-0000-0000-00000000c001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c001","role":"OPERATOR","permissions":["financial:read"]}}';

SELECT is(
  public.current_perms_v(),
  0::bigint,
  'revoked grant excluded → version returns 0');

-- ── 7. user_tenant_roles published on supabase_realtime (scoped push) ─────────
RESET ROLE;
SELECT is(
  (SELECT count(*)::int
     FROM pg_publication_tables
    WHERE pubname    = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename  = 'user_tenant_roles'),
  1,
  'user_tenant_roles is published on supabase_realtime (RLS-gated push)');

SELECT * FROM finish();
ROLLBACK;
