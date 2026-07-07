-- =============================================================================
-- pgTAP: revoke_user_sessions RPC (Pilar 1.5 Kill-Session)
-- Migration: 20260910000002_tenant_rbac_revoke_sessions
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- ── Stub net.http_post if pg_net is not installed ─────────────────────────────
-- pg_net is async: real calls return immediately with a request ID; failures
-- are reported out-of-band. In test DBs without pg_net, we stub the function
-- so the audit INSERT (which happens BEFORE the call) is not rolled back.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_net'
  ) THEN
    EXECUTE 'CREATE SCHEMA IF NOT EXISTS net';
    EXECUTE $f$
      CREATE FUNCTION net.http_post(
        url                  text,
        body                 text     DEFAULT NULL,
        params               jsonb    DEFAULT '{}'::jsonb,
        headers              jsonb    DEFAULT '{}'::jsonb,
        timeout_milliseconds integer  DEFAULT 2000
      ) RETURNS bigint LANGUAGE sql AS $body$ SELECT 0::bigint $body$
    $f$;
  END IF;
END;
$$;

-- ── Fixture ───────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-000000001002', 'Revoke Org A', 'Revoke Org A SA', '00000000000011',
   'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
   'rev-a@test.com', 'EXT_REV_A', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-000000001003', 'Revoke Org B', 'Revoke Org B SA', '00000000000012',
   'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
   'rev-b@test.com', 'EXT_REV_B', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- user_roles has FK to auth.users — bypass with replica role (established pattern).
SET LOCAL session_replication_role = replica;
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
  ('00000000-0000-0000-0000-000000001021', '00000000-0000-0000-0000-000000001002', 'TENANT_ADMIN'),
  ('00000000-0000-0000-0000-000000001022', '00000000-0000-0000-0000-000000001002', 'AUDITOR')
ON CONFLICT (user_id) DO UPDATE
  SET organization_id = EXCLUDED.organization_id, role = EXCLUDED.role;
SET LOCAL session_replication_role = DEFAULT;

-- ── 1. Function exists ────────────────────────────────────────────────────────
SELECT has_function(
  'public', 'revoke_user_sessions', ARRAY['uuid'],
  'revoke_user_sessions(uuid) is registered');

-- ── 2. Caller without roles:manage is denied (42501) ─────────────────────────
-- User 1022 is AUDITOR — no roles:manage in JWT.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000001022","organization_id":"00000000-0000-0000-0000-000000001002","app_metadata":{"org_id":"00000000-0000-0000-0000-000000001002","role":"AUDITOR","permissions":[]}}';

SELECT throws_ok(
  $$ SELECT public.revoke_user_sessions(
       '00000000-0000-0000-0000-000000001022'::uuid
     ) $$,
  '42501',
  NULL,
  'AUDITOR without roles:manage cannot call revoke_user_sessions');

-- ── 3. Cross-org target blocked (INV-22 / INV-26 not-found parity) ───────────
-- User 1021 (org A, TENANT_ADMIN /*) tries to revoke user 1023 (org B).
-- User 1023 is absent from user_roles for org A → "Not found." deny.
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000001021","organization_id":"00000000-0000-0000-0000-000000001002","app_metadata":{"org_id":"00000000-0000-0000-0000-000000001002","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT throws_ok(
  $$ SELECT public.revoke_user_sessions(
       '00000000-0000-0000-0000-000000001023'::uuid
     ) $$,
  '42501',
  'Not found.',
  'cross-org target treated as not-found (deny parity INV-26)');

-- ── 4-5. Success path: TENANT_ADMIN (org A) revokes user 1022 (same org) ────
-- JWT claims still set to user 1021 (TENANT_ADMIN, org A, permissions ["*"]).
-- net.http_post is either real (fire-and-forget, no exception) or stubbed above.
SELECT lives_ok(
  $$ SELECT public.revoke_user_sessions(
       '00000000-0000-0000-0000-000000001022'::uuid
     ) $$,
  'TENANT_ADMIN with roles:manage successfully calls revoke_user_sessions');

RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
    WHERE event_type = 'SESSIONS_REVOKED'
      AND organization_id = '00000000-0000-0000-0000-000000001002'),
  1,
  'SESSIONS_REVOKED audit row written before pg_net call (INV-21)');

SELECT is(
  (SELECT (payload ->> 'target_user')
     FROM public.system_audit_log
    WHERE event_type = 'SESSIONS_REVOKED'
      AND organization_id = '00000000-0000-0000-0000-000000001002'
    LIMIT 1),
  '00000000-0000-0000-0000-000000001022',
  'audit payload contains correct target_user');

SELECT * FROM finish();
ROLLBACK;
