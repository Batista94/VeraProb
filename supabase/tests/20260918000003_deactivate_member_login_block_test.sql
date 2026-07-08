-- =============================================================================
-- pgTAP: Deactivate Member Login Block (20260918000003)
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ── 1. Setup Data ────────────────────────────────────────────────────────────
-- Create Organization
INSERT INTO public.organizations (id, name, legal_name) 
VALUES ('00000000-0000-0000-0000-0000000008d1', 'Test Org', 'Test Org SA');

-- Create Admin User
INSERT INTO auth.users (id, email, email_confirmed_at) 
VALUES ('00000000-0000-0000-0000-000000000801', 'admin@veraprob.test', NOW());

INSERT INTO public.user_roles (user_id, organization_id, role, user_email, is_active)
VALUES ('00000000-0000-0000-0000-000000000801', '00000000-0000-0000-0000-0000000008d1', 'TENANT_ADMIN', 'admin@veraprob.test', true);

-- Create Target User
INSERT INTO auth.users (id, email, email_confirmed_at) 
VALUES ('00000000-0000-0000-0000-000000000802', 'target@veraprob.test', NOW());

INSERT INTO public.user_roles (user_id, organization_id, role, user_email, is_active)
VALUES ('00000000-0000-0000-0000-000000000802', '00000000-0000-0000-0000-0000000008d1', 'OPERATOR', 'target@veraprob.test', true);

-- Set caller to Admin
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000000801","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000008d1","role":"TENANT_ADMIN"}}';

-- ── 2. Test Deactivate ───────────────────────────────────────────────────────
SELECT lives_ok(
  $$ SELECT public.deactivate_member('00000000-0000-0000-0000-000000000802'::uuid) $$,
  'deactivate_member executes without error'
);

SELECT results_eq(
  $$ SELECT is_active FROM public.user_roles WHERE user_id = '00000000-0000-0000-0000-000000000802'::uuid $$,
  $$ VALUES (false) $$,
  'deactivate_member sets is_active to false'
);

SELECT results_eq(
  $$ SELECT banned_until FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000802'::uuid $$,
  $$ VALUES ('infinity'::timestamptz) $$,
  'deactivate_member sets banned_until to infinity'
);

-- ── 3. Test JWT Hook ─────────────────────────────────────────────────────────
-- Simulate token creation for the deactivated user
SELECT results_eq(
  $$ 
    SELECT (public.custom_access_token_hook(
      jsonb_build_object(
        'user_id', '00000000-0000-0000-0000-000000000802',
        'claims', jsonb_build_object()
      )
    ) -> 'claims' -> 'app_metadata' ->> 'org_id')::text
  $$,
  $$ VALUES (NULL::text) $$,
  'custom_access_token_hook returns org_id=null for deactivated user'
);

SELECT results_eq(
  $$ 
    SELECT (public.custom_access_token_hook(
      jsonb_build_object(
        'user_id', '00000000-0000-0000-0000-000000000802',
        'claims', jsonb_build_object()
      )
    ) -> 'claims' -> 'app_metadata' ->> 'permissions')::text
  $$,
  $$ VALUES ('[]') $$,
  'custom_access_token_hook returns permissions=[] for deactivated user'
);

-- ── 4. Test Reactivate ───────────────────────────────────────────────────────
SELECT lives_ok(
  $$ SELECT public.reactivate_member('00000000-0000-0000-0000-000000000802'::uuid) $$,
  'reactivate_member executes without error'
);

SELECT results_eq(
  $$ SELECT banned_until FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000802'::uuid $$,
  $$ VALUES (NULL::timestamptz) $$,
  'reactivate_member clears banned_until'
);

SELECT * FROM finish();
ROLLBACK;
