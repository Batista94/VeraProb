-- =============================================================================
-- pgTAP: Auto-kill sessions on sensitive role revocation (Pilar 1.5.B)
-- Migration: 20260910000003_tenant_rbac_auto_revoke_sessions
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Stub net.http_post if pg_net is installed but GUC not configured.
-- Mirrors the approach in 20260910000002 test.
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

SELECT plan(5);

-- ── Fixture ───────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-000000001004',
  'Auto-Kill Org', 'Auto-Kill Org SA', '00000000000013',
  'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
  'ak@test.com', 'EXT_AK', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

-- user_roles: bypass FK to auth.users (established pattern).
SET LOCAL session_replication_role = replica;
INSERT INTO public.user_roles (user_id, organization_id, role) VALUES
  ('00000000-0000-0000-0000-000000001041', '00000000-0000-0000-0000-000000001004', 'TENANT_ADMIN'),
  ('00000000-0000-0000-0000-000000001042', '00000000-0000-0000-0000-000000001004', 'AUDITOR')
ON CONFLICT (user_id) DO UPDATE
  SET organization_id = EXCLUDED.organization_id, role = EXCLUDED.role;
SET LOCAL session_replication_role = DEFAULT;

-- Sensitive role: contains sla:approve (is_sensitive = true).
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-000000001091',
   '00000000-0000-0000-0000-000000001004',
   'AK-Sensitive', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-000000001091', 'sla:approve')
ON CONFLICT DO NOTHING;

-- Non-sensitive role: contains telemetry:read (is_sensitive = false).
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-000000001092',
   '00000000-0000-0000-0000-000000001004',
   'AK-Safe', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-000000001092', 'telemetry:read')
ON CONFLICT DO NOTHING;

-- Assign both roles + a fallback role to user 1042.
-- The fallback ensures LastProfileGuard never fires during this test
-- (which focuses on session-revocation behavior, not last-profile protection).
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-000000001093',
   '00000000-0000-0000-0000-000000001004',
   'AK-Fallback', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.user_tenant_roles (
  user_id, tenant_role_id, organization_id, granted_by
) VALUES
  ('00000000-0000-0000-0000-000000001042',
   '00000000-0000-0000-0000-000000001091',
   '00000000-0000-0000-0000-000000001004',
   '00000000-0000-0000-0000-000000001041'),
  ('00000000-0000-0000-0000-000000001042',
   '00000000-0000-0000-0000-000000001092',
   '00000000-0000-0000-0000-000000001004',
   '00000000-0000-0000-0000-000000001041'),
  ('00000000-0000-0000-0000-000000001042',
   '00000000-0000-0000-0000-000000001093',
   '00000000-0000-0000-0000-000000001004',
   '00000000-0000-0000-0000-000000001041')
ON CONFLICT DO NOTHING;

-- ── 1. Revoking a SENSITIVE role triggers SESSIONS_REVOKED audit ──────────────
-- caller = admin (1041), target = auditor (1042), role = AK-Sensitive (sla:approve).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000001041","organization_id":"00000000-0000-0000-0000-000000001004","app_metadata":{"org_id":"00000000-0000-0000-0000-000000001004","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.revoke_tenant_role(
       '00000000-0000-0000-0000-000000001042'::uuid,
       '00000000-0000-0000-0000-000000001091'::uuid
     ) $$,
  'revoke_tenant_role on sensitive role completes without exception');

-- ── 2. Revoking a NON-sensitive role does NOT trigger SESSIONS_REVOKED ─────────
SELECT lives_ok(
  $$ SELECT public.revoke_tenant_role(
       '00000000-0000-0000-0000-000000001042'::uuid,
       '00000000-0000-0000-0000-000000001092'::uuid
     ) $$,
  'revoke_tenant_role on non-sensitive role completes without exception');

RESET ROLE;

-- ── 3. ROLE_REVOKED audit written for both calls ──────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
    WHERE event_type = 'ROLE_REVOKED'
      AND organization_id = '00000000-0000-0000-0000-000000001004'),
  2,
  'ROLE_REVOKED audit row written for each revocation');

-- ── 4. SESSIONS_REVOKED written only for the sensitive revocation ─────────────
SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
    WHERE event_type = 'SESSIONS_REVOKED'
      AND organization_id = '00000000-0000-0000-0000-000000001004'),
  1,
  'SESSIONS_REVOKED written only once (sensitive role revocation triggers auto-kill)');

-- ── 5. Grant row is soft-revoked (append-only, INV-3) ────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.user_tenant_roles
    WHERE user_id = '00000000-0000-0000-0000-000000001042'
      AND revoked_at IS NOT NULL),
  2,
  'both roles soft-revoked (revoked_at set, row preserved for audit trail)');

SELECT * FROM finish();
ROLLBACK;
