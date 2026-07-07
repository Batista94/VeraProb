-- =============================================================================
-- pgTAP: Tenant Roles and Permissions Expansion (20260915000001)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(1);

-- ── 1. Assert new permissions exist ──────────────────────────────────────────

SELECT results_eq(
  $$ SELECT key FROM public.tenant_permissions WHERE key IN ('users:manage', 'roles:read', 'org:manage') ORDER BY key $$,
  $$ VALUES ('org:manage'), ('roles:read'), ('users:manage') $$,
  'New granular permissions (users:manage, roles:read, org:manage) are seeded correctly'
);

SELECT * FROM finish();
ROLLBACK;
