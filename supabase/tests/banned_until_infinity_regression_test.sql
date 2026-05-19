-- =============================================================================
-- pgTAP: banned_until='infinity' regression guard (CI Gate)
--
-- WHY: PostgreSQL accepts 'infinity' as a valid TIMESTAMPTZ literal, but GoTrue
-- (the Go auth server bundled with Supabase) uses time.Time internally, which
-- cannot parse the 'infinity' literal. Any row with banned_until='infinity' in
-- auth.users causes GoTrue to return HTTP 500 with:
--   {"message":"Database error finding users"}
-- on ALL /auth/v1/admin/users calls, breaking the entire SuperAdmin tenant list.
--
-- HOW THE BUG RE-ENTERS:
--   1. Any SQL that sets banned_until = 'infinity'::timestamptz
--   2. Any RPC that directly banns users with infinity sentinel
--
-- THIS TEST GUARDS AGAINST:
--   1. Existing infinity rows in auth.users (data integrity)
--   2. The super_admin_archive_organization RPC re-introducing the literal
--
-- Run via: supabase test
-- Related migration: 20260519000001_fix_banned_until_infinity.sql
-- =============================================================================

BEGIN;
SELECT plan(2);

-- ── Test 1: No auth.users rows have banned_until = 'infinity' ─────────────────
-- If this fails: run migration 20260519000001_fix_banned_until_infinity.sql
SELECT is(
  (SELECT COUNT(*)::int FROM auth.users WHERE banned_until = 'infinity'::timestamptz),
  0,
  'GoTrue guard: no auth.users rows have banned_until = infinity'
);

-- ── Test 2: super_admin_archive_organization RPC body does not set infinity ────
-- Checks the live function definition in pg_proc to catch any future edits
-- that accidentally revert to the infinity sentinel.
-- The pattern matches: banned_until = 'infinity' (with optional whitespace)
-- but does NOT match comments like: -- FIX: was 'infinity'
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_proc p
    JOIN   pg_namespace n ON p.pronamespace = n.oid
    WHERE  n.nspname = 'public'
      AND  p.proname = 'super_admin_archive_organization'
      AND  p.prosrc ~ 'banned_until\s*=\s*''infinity'''
  ),
  'super_admin_archive_organization: banned_until assignment does not use infinity literal'
);

SELECT * FROM finish();
ROLLBACK;
