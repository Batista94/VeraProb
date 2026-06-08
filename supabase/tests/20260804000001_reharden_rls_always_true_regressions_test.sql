BEGIN;
SELECT plan(7);

-- NOTE: spatial_ref_sys grants are NOT asserted here — they are owned by
-- supabase_admin and cannot be revoked by the postgres migration role (see the
-- migration header §A). The standing inv22 invariant test asserts the table
-- carries no tenant column instead.

-- ── B. telegram_pending_links — permissive policy gone, anon closed ───────────
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'telegram_pending_links'
      AND policyname = 'tpl_service_all'
  ),
  'tpl_service_all permissive policy is dropped (regression closed)'
);
SELECT is(
  (SELECT permissive::text FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'telegram_pending_links'
     AND policyname = 'deny-all anon: telegram_pending_links'),
  'RESTRICTIVE',
  'telegram_pending_links has RESTRICTIVE deny-all for anon'
);
SELECT ok(
  NOT has_table_privilege('anon', 'public.telegram_pending_links', 'SELECT'),
  'anon has NO SELECT grant on telegram_pending_links'
);

-- ── C. telegram_status_queries — INSERT scoped to service_role only ───────────
SELECT is(
  (SELECT roles::text FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'telegram_status_queries'
     AND policyname = 'tsq_insert_service'),
  '{service_role}',
  'tsq_insert_service is scoped to service_role only'
);
SELECT is(
  (SELECT permissive::text FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'telegram_status_queries'
     AND policyname = 'deny-all insert: telegram_status_queries'),
  'RESTRICTIVE',
  'telegram_status_queries has RESTRICTIVE deny-all INSERT for authenticated'
);

-- ── Omnibus: no always-true permissive policy for client roles on these tables ─
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('telegram_pending_links', 'telegram_status_queries')
      AND permissive = 'PERMISSIVE'
      AND (qual = 'true' OR with_check = 'true')
      AND (roles::text[] && ARRAY['public','authenticated','anon']::text[] OR roles::text = '{}')
  ),
  'No always-true permissive policy for client roles on the re-hardened tables'
);

-- ── Inverse: service_role retains operational access (bypasses RLS) ───────────
SELECT ok(
  has_table_privilege('service_role', 'public.telegram_pending_links', 'INSERT'),
  'service_role retains INSERT on telegram_pending_links (bot/webhook flow intact)'
);

SELECT * FROM finish();
ROLLBACK;
