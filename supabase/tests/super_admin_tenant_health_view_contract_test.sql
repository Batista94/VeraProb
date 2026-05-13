-- =============================================================================
-- pgTAP: super_admin_tenant_health_view column contract (INV-3, INV-6, INV-22)
--
-- Guards against regressions where a DROP+CREATE migration omits columns that
-- the super-admin-proxy Edge Function selects explicitly (cnpj, created_at).
-- A missing column causes PostgREST to return 400 → 500 to the Flutter client.
--
-- Run via: supabase test db
-- =============================================================================

BEGIN;
SELECT plan(5);

-- ── Test 1: cnpj column exists in the view ────────────────────────────────────
SELECT has_column(
  'public',
  'super_admin_tenant_health_view',
  'cnpj',
  'INV-3: super_admin_tenant_health_view must expose cnpj column'
);

-- ── Test 2: created_at column exists in the view ──────────────────────────────
SELECT has_column(
  'public',
  'super_admin_tenant_health_view',
  'created_at',
  'INV-3: super_admin_tenant_health_view must expose created_at column'
);

-- ── Test 3: created_at is TIMESTAMPTZ (INV-6) ─────────────────────────────────
SELECT col_type_is(
  'public',
  'super_admin_tenant_health_view',
  'created_at',
  'timestamp with time zone',
  'INV-6: created_at must be TIMESTAMPTZ (not bare timestamp)'
);

-- ── Test 4: view has security_invoker = true (INV-22) ─────────────────────────
SELECT is(
  (SELECT (relacl IS NOT NULL OR reloptions::text LIKE '%security_invoker=true%')
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname = 'super_admin_tenant_health_view'
     AND c.relkind = 'v'),
  true,
  'INV-22: view must have security_invoker=true'
);

-- ── Test 5: authenticated role has NO SELECT on the view (INV-24) ─────────────
SELECT is(
  has_table_privilege('authenticated', 'public.super_admin_tenant_health_view', 'SELECT'),
  false,
  'INV-24: authenticated role must NOT have SELECT on super_admin_tenant_health_view'
);

SELECT * FROM finish();
ROLLBACK;
