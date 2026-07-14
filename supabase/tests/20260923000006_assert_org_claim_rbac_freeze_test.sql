-- =============================================================================
-- pgTAP: 20260923000006_assert_org_claim_rbac_freeze
-- CIA: C+I — INV-1 / INV-22 / INV-26 JWT org claim red-team
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

SELECT has_function(
  'public',
  'assert_org_claim',
  ARRAY['uuid'],
  'assert_org_claim(uuid) exists'
);

-- No JWT → no-op (postgres session)
SELECT lives_ok(
  $$SELECT public.assert_org_claim('00000000-0000-0000-0000-000000000001'::uuid)$$,
  'assert_org_claim allows null JWT (service/postgres)'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_description d
    JOIN pg_class c ON c.oid = d.objoid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'tenant_roles'
      AND d.description ILIKE '%FREEZE%'
  ),
  'tenant_roles freeze comment present'
);

-- ── Red-team: JWT mismatch → 42501 opaque (INV-26) ───────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000c6b1","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000c6a1","role":"AUDITOR"}}';

SELECT throws_ok(
  $$ SELECT public.assert_org_claim('00000000-0000-0000-0000-00000000c6a2'::uuid) $$,
  '42501',
  'not found',
  'JWT org A + assert_org_claim(org B) → 42501 not found (INV-26)'
);

SELECT lives_ok(
  $$ SELECT public.assert_org_claim('00000000-0000-0000-0000-00000000c6a1'::uuid) $$,
  'JWT org A + assert_org_claim(org A) lives'
);

SELECT throws_ok(
  $$ SELECT public.assert_org_claim(NULL) $$,
  '42501',
  'organization_id required',
  'p_org_id NULL → 42501'
);

RESET ROLE;

-- service_role claim bypasses org match
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims =
  '{"role":"service_role","sub":"service"}';

SELECT lives_ok(
  $$ SELECT public.assert_org_claim('00000000-0000-0000-0000-00000000c6ff'::uuid) $$,
  'service_role + arbitrary org lives'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
