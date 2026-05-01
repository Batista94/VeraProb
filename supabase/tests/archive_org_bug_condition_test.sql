-- =============================================================================
-- pgTAP: Bug Condition Exploration — Archive Crashes on Column Mismatch
-- =============================================================================
-- **Validates: Requirements 1.1, 1.2, 1.3, 2.1**
--
-- Property 1 (Bug Condition): For ALL valid archive requests where
--   isBugCondition(X) holds (org exists, status NOT IN ('ARCHIVED','DELETED'),
--   caller is super_admin), the RPC super_admin_archive_organization SHALL
--   complete without error and set organizations.status = 'ARCHIVED'.
--
-- EXPECTED ON UNFIXED CODE: All lives_ok assertions FAIL because step E
--   references non-existent column `target_organization_id` instead of
--   `target_org_id` in impersonation_sessions.
--
-- EXPECTED ON FIXED CODE: All assertions PASS.
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

-- ── Scenario A: ACTIVE org, 0 impersonation sessions ────────────────────────
-- Bug condition: org exists, status = ACTIVE, caller is super_admin
-- Expected: RPC completes, org.status = 'ARCHIVED'
-- On unfixed code: crashes at step E with column "target_organization_id" does not exist

DO $$ BEGIN
  PERFORM set_config('test.org_a', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (current_setting('test.org_a')::uuid, 'PBT-Org-A-NoSessions-' || substr(md5(random()::text), 1, 8), 'ACTIVE');

SELECT lives_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.org_a'),
    'PBT: sunset org with 0 sessions',
    current_setting('test.super_admin_id')
  ),
  'Req 1.1/2.1: Archive ACTIVE org with 0 impersonation sessions completes without error'
);

SELECT is(
  (SELECT status FROM public.organizations WHERE id = current_setting('test.org_a')::uuid),
  'ARCHIVED',
  'Req 2.1: Org status is ARCHIVED after successful archive (0 sessions)'
);

-- ── Scenario B: ACTIVE org, 1 active impersonation session ──────────────────
-- Bug condition: org exists, status = ACTIVE, caller is super_admin
-- Expected: RPC completes, session revoked, org.status = 'ARCHIVED'
-- On unfixed code: crashes at step E (column error)

DO $$ BEGIN
  PERFORM set_config('test.org_b', gen_random_uuid()::text, false);
  PERFORM set_config('test.impersonator_b1', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (current_setting('test.org_b')::uuid, 'PBT-Org-B-1Session-' || substr(md5(random()::text), 1, 8), 'ACTIVE');

INSERT INTO public.impersonation_sessions
  (impersonator_user_id, target_org_id, issued_at, expires_at, ticket_id)
VALUES
  (current_setting('test.impersonator_b1')::uuid,
   current_setting('test.org_b')::uuid,
   NOW(), NOW() + interval '30 minutes', 'TICKET-PBT-B1');

SELECT lives_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.org_b'),
    'PBT: sunset org with 1 active session',
    current_setting('test.super_admin_id')
  ),
  'Req 1.2/2.1: Archive ACTIVE org with 1 active impersonation session completes without error'
);

SELECT is(
  (SELECT status FROM public.organizations WHERE id = current_setting('test.org_b')::uuid),
  'ARCHIVED',
  'Req 2.1: Org status is ARCHIVED after successful archive (1 session)'
);

-- ── Scenario C: ACTIVE org, 3 active impersonation sessions ─────────────────
-- Bug condition: org exists, status = ACTIVE, caller is super_admin
-- Multiple sessions from different impersonators (trigger enforces max 1 per user)
-- On unfixed code: crashes at step E (column error)

DO $$ BEGIN
  PERFORM set_config('test.org_c', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (current_setting('test.org_c')::uuid, 'PBT-Org-C-3Sessions-' || substr(md5(random()::text), 1, 8), 'ACTIVE');

-- 3 different impersonators, each with 1 active session targeting org_c
INSERT INTO public.impersonation_sessions
  (impersonator_user_id, target_org_id, issued_at, expires_at, ticket_id)
VALUES
  (gen_random_uuid(), current_setting('test.org_c')::uuid,
   NOW(), NOW() + interval '30 minutes', 'TICKET-PBT-C1'),
  (gen_random_uuid(), current_setting('test.org_c')::uuid,
   NOW(), NOW() + interval '30 minutes', 'TICKET-PBT-C2'),
  (gen_random_uuid(), current_setting('test.org_c')::uuid,
   NOW(), NOW() + interval '30 minutes', 'TICKET-PBT-C3');

SELECT lives_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.org_c'),
    'PBT: sunset org with 3 active sessions',
    current_setting('test.super_admin_id')
  ),
  'Req 1.2/2.1: Archive ACTIVE org with 3 active impersonation sessions completes without error'
);

SELECT is(
  (SELECT status FROM public.organizations WHERE id = current_setting('test.org_c')::uuid),
  'ARCHIVED',
  'Req 2.1: Org status is ARCHIVED after successful archive (3 sessions)'
);

-- ── Scenario D: ACTIVE org, only expired sessions ───────────────────────────
-- Bug condition: org exists, status = ACTIVE, caller is super_admin
-- PostgreSQL validates column names at parse time regardless of matching rows
-- On unfixed code: crashes at step E (column error even with 0 matching rows)

DO $$ BEGIN
  PERFORM set_config('test.org_d', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (current_setting('test.org_d')::uuid, 'PBT-Org-D-ExpiredOnly-' || substr(md5(random()::text), 1, 8), 'ACTIVE');

-- Expired session (expires_at in the past, already revoked)
INSERT INTO public.impersonation_sessions
  (impersonator_user_id, target_org_id, issued_at, expires_at, revoked_at, ticket_id)
VALUES
  (gen_random_uuid(), current_setting('test.org_d')::uuid,
   NOW() - interval '2 hours', NOW() - interval '90 minutes',
   NOW() - interval '90 minutes', 'TICKET-PBT-D1');

SELECT lives_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.org_d'),
    'PBT: sunset org with only expired sessions',
    current_setting('test.super_admin_id')
  ),
  'Req 1.3/2.1: Archive ACTIVE org with only expired impersonation sessions completes without error'
);

SELECT is(
  (SELECT status FROM public.organizations WHERE id = current_setting('test.org_d')::uuid),
  'ARCHIVED',
  'Req 2.1: Org status is ARCHIVED after successful archive (expired sessions only)'
);

-- ── Scenario E: ACTIVE org, mixed active + already-revoked sessions ──────────
-- Bug condition: org exists, status = ACTIVE, caller is super_admin
-- Tests with a mix of active and already-revoked sessions
-- On unfixed code: crashes at step E (column error)

DO $$ BEGIN
  PERFORM set_config('test.org_e', gen_random_uuid()::text, false);
END $$;

INSERT INTO public.organizations (id, name, status)
VALUES (current_setting('test.org_e')::uuid, 'PBT-Org-E-Mixed-' || substr(md5(random()::text), 1, 8), 'ACTIVE');

-- 1 active + 1 expired session from different impersonators
INSERT INTO public.impersonation_sessions
  (impersonator_user_id, target_org_id, issued_at, expires_at, ticket_id)
VALUES
  (gen_random_uuid(), current_setting('test.org_e')::uuid,
   NOW(), NOW() + interval '30 minutes', 'TICKET-PBT-E1');

INSERT INTO public.impersonation_sessions
  (impersonator_user_id, target_org_id, issued_at, expires_at, revoked_at, ticket_id)
VALUES
  (gen_random_uuid(), current_setting('test.org_e')::uuid,
   NOW() - interval '2 hours', NOW() - interval '90 minutes',
   NOW() - interval '90 minutes', 'TICKET-PBT-E2');

SELECT lives_ok(
  format(
    'SELECT public.super_admin_archive_organization(%L::uuid, %L, %L::uuid)',
    current_setting('test.org_e'),
    'PBT: sunset ACTIVE org with mixed sessions',
    current_setting('test.super_admin_id')
  ),
  'Req 1.1/2.1: Archive ACTIVE org with mixed active+revoked sessions completes without error'
);

SELECT is(
  (SELECT status FROM public.organizations WHERE id = current_setting('test.org_e')::uuid),
  'ARCHIVED',
  'Req 2.1: Org status is ARCHIVED after successful archive (mixed active+revoked sessions)'
);

SELECT * FROM finish();
ROLLBACK;
