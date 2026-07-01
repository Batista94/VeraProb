-- =============================================================================
-- pgTAP: super_admin_archive_organization — concurrency fix (20260905000004)
-- =============================================================================
-- Sequential contract guard for the lock-then-check rewrite. True concurrency
-- (K racing calls → exactly 1 audit row) is covered by the Dart property test
-- property_double_click_idempotency_test.dart — dblink self-connect is blocked
-- in local Supabase, so parallelism cannot be exercised from a single pgTAP
-- session. Here we assert the post-fix single-caller invariants: a successful
-- archive writes exactly ONE 'ORG_ARCHIVED' audit row, and the P0003
-- idempotency error still fires on re-archive.
--
-- No JWT context (auth.uid() IS NULL) → JWT guard skipped (service_role path).
-- =============================================================================

BEGIN;
SELECT plan(4);

INSERT INTO public.organizations (id, name)
VALUES ('d4000000-0000-0000-0000-000000000001', 'PBT-ConcFix-Archive');

-- Test 1: archiving an ACTIVE org succeeds
SELECT lives_ok(
  $$ SELECT public.super_admin_archive_organization(
       'd4000000-0000-0000-0000-000000000001'::uuid,
       'concurrency fix sequential guard',
       '00000000-0000-0000-0000-ffffffffffff'::uuid) $$,
  'Archive of an ACTIVE org succeeds'
);

-- Test 2: status transitions to ARCHIVED
SELECT is(
  (SELECT status FROM public.organizations
   WHERE id = 'd4000000-0000-0000-0000-000000000001'),
  'ARCHIVED',
  'Org status is ARCHIVED after archive'
);

-- Test 3 (INV-3): exactly one ORG_ARCHIVED audit record
SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
   WHERE organization_id = 'd4000000-0000-0000-0000-000000000001'
     AND event_type = 'ORG_ARCHIVED'),
  1,
  'Exactly one ORG_ARCHIVED audit record written'
);

-- Test 4 (INV-10): re-archiving an already-ARCHIVED org raises P0003
SELECT throws_ok(
  $$ SELECT public.super_admin_archive_organization(
       'd4000000-0000-0000-0000-000000000001'::uuid,
       're-archive attempt',
       '00000000-0000-0000-0000-ffffffffffff'::uuid) $$,
  'P0003',
  NULL,
  'Re-archiving an already-ARCHIVED org raises P0003'
);

SELECT * FROM finish();
ROLLBACK;
