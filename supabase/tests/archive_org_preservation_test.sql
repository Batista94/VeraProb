-- =============================================================================
-- pgTAP: Preservation Property — Guard Behavior Unchanged
-- =============================================================================
-- **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
--
-- Property 2 (Preservation): For ALL inputs where NOT isBugCondition(X)
--   (unauthorized caller, non-existent/DELETED org, already-ARCHIVED org),
--   the RPC super_admin_archive_organization SHALL produce the same error
--   codes as observed on UNFIXED code.
--
-- Three guard categories tested:
--   Category 1 — JWT guard (INV-6): non-super-admin → insufficient_privilege
--   Category 2 — 404-parity (INV-26): non-existent/DELETED → P0002
--   Category 3 — Idempotency: already-ARCHIVED → P0003
--
-- EXPECTED ON UNFIXED CODE: All tests PASS — guards fire BEFORE step E,
--   so the column mismatch bug is never reached.
--
-- EXPECTED ON FIXED CODE: All tests PASS — guards are unchanged by the fix.
--
-- Run via: supabase test
-- =============================================================================

BEGIN;
SELECT plan(10);

-- ── Helpers: deterministic super_admin UUID ──────────────────────────────────
DO $$ BEGIN
  PERFORM set_config('test.super_admin_id',
    '00000000-0000-0000-0000-ffffffffffff', false);
END $$;

-- =============================================================================
-- Category 1: JWT Guard — Non-super-admin caller → insufficient_privilege
-- (INV-6 / Req 3.1)
--
-- Observation on UNFIXED code: When auth.uid() IS NOT NULL and
-- app_metadata.super_admin is not 'true', the RPC raises
-- 'insufficient_privilege' (SQLSTATE 42501) before reaching any other step.
-- =============================================================================

-- Test 1.1: Caller with empty app_metadata (no super_admin claim at all)
-- Simulate authenticated user with no super_admin claim via JWT GUC
SELECT set_config(
  'request.jwt.claims',
  format('{"sub": "%s", "role": "authenticated", "app_metadata": {}}', gen_random_uuid()),
  true
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    gen_random_uuid(),
    'PBT: unauthorized empty metadata',
    current_setting('test.super_admin_id')
  ),
  '42501',
  NULL,
  'Req 3.1/INV-6: Empty app_metadata caller → insufficient_privilege'
);

-- Test 1.2: Caller with super_admin explicitly set to false
SELECT set_config(
  'request.jwt.claims',
  format('{"sub": "%s", "role": "authenticated", "app_metadata": {"super_admin": false}}', gen_random_uuid()),
  true
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    gen_random_uuid(),
    'PBT: unauthorized super_admin=false',
    current_setting('test.super_admin_id')
  ),
  '42501',
  NULL,
  'Req 3.1/INV-6: super_admin=false caller → insufficient_privilege'
);

-- Test 1.3: Caller with super_admin set to a non-true string
SELECT set_config(
  'request.jwt.claims',
  format('{"sub": "%s", "role": "authenticated", "app_metadata": {"super_admin": "yes"}}', gen_random_uuid()),
  true
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    gen_random_uuid(),
    'PBT: unauthorized super_admin=yes (not true)',
    current_setting('test.super_admin_id')
  ),
  '42501',
  NULL,
  'Req 3.1/INV-6: super_admin="yes" (not "true") caller → insufficient_privilege'
);

-- Reset JWT claims so subsequent tests run without auth context
SELECT set_config('request.jwt.claims', '', true);

-- =============================================================================
-- Category 2: 404-Parity — Non-existent or DELETED org → P0002
-- (INV-26 / Req 3.2)
--
-- Observation on UNFIXED code: When org does not exist or has status='DELETED',
-- the RPC raises error code P0002 before reaching step E.
-- No JWT context → auth.uid() IS NULL → JWT guard skipped → 404 guard fires.
-- =============================================================================

-- Test 2.1: Completely non-existent org (random UUID not in organizations table)
SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    gen_random_uuid(),
    'PBT: non-existent org ' || substr(md5(random()::text), 1, 8),
    current_setting('test.super_admin_id')
  ),
  'P0002',
  NULL,
  'Req 3.2/INV-26: Non-existent org (random UUID) → P0002'
);

-- Test 2.2: Another random non-existent org (property: holds for ALL random UUIDs)
SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    gen_random_uuid(),
    'PBT: non-existent org ' || substr(md5(random()::text), 1, 8),
    current_setting('test.super_admin_id')
  ),
  'P0002',
  NULL,
  'Req 3.2/INV-26: Non-existent org (second random UUID) → P0002'
);

-- Test 2.3: DELETED org — exists in table but status = 'DELETED'
DO $$ BEGIN
  PERFORM set_config('test.deleted_org', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (
  current_setting('test.deleted_org')::uuid,
  'PBT-Org-Deleted-' || substr(md5(random()::text), 1, 8),
  'DELETED'
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.deleted_org'),
    'PBT: DELETED org should 404',
    current_setting('test.super_admin_id')
  ),
  'P0002',
  NULL,
  'Req 3.2/INV-26: DELETED org → P0002 (same as non-existent)'
);

-- Test 2.4: Another DELETED org (property: holds for ALL deleted orgs)
DO $$ BEGIN
  PERFORM set_config('test.deleted_org_2', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (
  current_setting('test.deleted_org_2')::uuid,
  'PBT-Org-Deleted2-' || substr(md5(random()::text), 1, 8),
  'DELETED'
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.deleted_org_2'),
    'PBT: second DELETED org should 404',
    current_setting('test.super_admin_id')
  ),
  'P0002',
  NULL,
  'Req 3.2/INV-26: Second DELETED org → P0002 (property holds across inputs)'
);

-- =============================================================================
-- Category 3: Idempotency Guard — Already-ARCHIVED org → P0003
-- (Req 3.3)
--
-- Observation on UNFIXED code: When org exists with status='ARCHIVED',
-- the RPC raises error code P0003 before reaching step E.
-- No JWT context → auth.uid() IS NULL → JWT guard skipped.
-- Org exists and status <> 'DELETED' → 404 guard passes.
-- Status = 'ARCHIVED' → idempotency guard fires.
-- =============================================================================

-- Test 3.1: Already-ARCHIVED org (basic case)
DO $$ BEGIN
  PERFORM set_config('test.archived_org_1', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (
  current_setting('test.archived_org_1')::uuid,
  'PBT-Org-Archived1-' || substr(md5(random()::text), 1, 8),
  'ARCHIVED'
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.archived_org_1'),
    'PBT: already archived org',
    current_setting('test.super_admin_id')
  ),
  'P0003',
  NULL,
  'Req 3.3: Already-ARCHIVED org → P0003 (idempotency guard)'
);

-- Test 3.2: Another already-ARCHIVED org (property: holds for ALL archived orgs)
DO $$ BEGIN
  PERFORM set_config('test.archived_org_2', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (
  current_setting('test.archived_org_2')::uuid,
  'PBT-Org-Archived2-' || substr(md5(random()::text), 1, 8),
  'ARCHIVED'
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.archived_org_2'),
    'PBT: second already archived org',
    current_setting('test.super_admin_id')
  ),
  'P0003',
  NULL,
  'Req 3.3: Second already-ARCHIVED org → P0003 (property holds across inputs)'
);

-- Test 3.3: Third already-ARCHIVED org with random reason string
DO $$ BEGIN
  PERFORM set_config('test.archived_org_3', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (
  current_setting('test.archived_org_3')::uuid,
  'PBT-Org-Archived3-' || substr(md5(random()::text), 1, 8),
  'ARCHIVED'
);

SELECT throws_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.archived_org_3'),
    'PBT: reason-' || substr(md5(random()::text), 1, 16),
    current_setting('test.super_admin_id')
  ),
  'P0003',
  NULL,
  'Req 3.3: Third already-ARCHIVED org with random reason → P0003'
);

SELECT * FROM finish();
ROLLBACK;
