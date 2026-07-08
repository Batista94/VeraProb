-- =============================================================================
-- pgTAP: Tenant Member-Lifecycle Governance Audit — 20260917000001
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── Fixtures (superuser, pre-RLS) ────────────────────────────────────────────
INSERT INTO public.organizations (id, name, timezone, plan_type) VALUES
  ('00000000-0000-0000-0000-000000000bb1', 'Gov Org 1', 'America/Sao_Paulo', 'enterprise'),
  ('00000000-0000-0000-0000-000000000bb2', 'Gov Org 2', 'America/Sao_Paulo', 'enterprise')
ON CONFLICT DO NOTHING;

INSERT INTO auth.users (id, aud, role, email) VALUES
  ('00000000-0000-0000-0000-0000000000ba', 'authenticated', 'authenticated', 'admin1@gov.test'),
  ('00000000-0000-0000-0000-0000000000bb', 'authenticated', 'authenticated', 'target1@gov.test'),
  ('00000000-0000-0000-0000-0000000000bc', 'authenticated', 'authenticated', 'auditor1@gov.test'),
  ('00000000-0000-0000-0000-0000000000bd', 'authenticated', 'authenticated', 'operador1@gov.test'),
  ('00000000-0000-0000-0000-0000000000be', 'authenticated', 'authenticated', 'admin2@gov.test')
ON CONFLICT DO NOTHING;

SET LOCAL session_replication_role = replica;
INSERT INTO public.user_roles (user_id, organization_id, role, is_active, user_email, organization_name) VALUES
  ('00000000-0000-0000-0000-0000000000ba', '00000000-0000-0000-0000-000000000bb1', 'TENANT_ADMIN', true, 'admin1@gov.test', 'Gov Org 1'),
  ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-000000000bb1', 'OPERATOR',     true, 'target1@gov.test', 'Gov Org 1'),
  ('00000000-0000-0000-0000-0000000000bc', '00000000-0000-0000-0000-000000000bb1', 'AUDITOR',      true, 'auditor1@gov.test', 'Gov Org 1'),
  ('00000000-0000-0000-0000-0000000000bd', '00000000-0000-0000-0000-000000000bb1', 'OPERATOR',     true, 'operador1@gov.test', 'Gov Org 1'),
  ('00000000-0000-0000-0000-0000000000be', '00000000-0000-0000-0000-000000000bb2', 'TENANT_ADMIN', true, 'admin2@gov.test', 'Gov Org 2')
ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;
SET LOCAL session_replication_role = DEFAULT;

-- ── Tests ──────────────────────────────────────────────────────────────────
-- Test 1: deactivate_member logs MEMBER_DEACTIVATED with actor+target identity
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000ba","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000bb1","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.deactivate_member('00000000-0000-0000-0000-0000000000bb') $$,
  'Admin deactivates target1'
);

SELECT is(
  (SELECT payload ->> 'target_email' FROM public.system_audit_log
    WHERE event_type = 'MEMBER_DEACTIVATED' AND organization_id = '00000000-0000-0000-0000-000000000bb1'
    ORDER BY occurred_at DESC LIMIT 1),
  'target1@gov.test',
  'MEMBER_DEACTIVATED event captures target_email'
);

SELECT is(
  (SELECT payload ->> 'actor_email' FROM public.system_audit_log
    WHERE event_type = 'MEMBER_DEACTIVATED' AND organization_id = '00000000-0000-0000-0000-000000000bb1'
    ORDER BY occurred_at DESC LIMIT 1),
  'admin1@gov.test',
  'MEMBER_DEACTIVATED event auto-embeds actor_email at the DB layer'
);

-- Test 2: reactivate_member logs MEMBER_REACTIVATED
SELECT lives_ok(
  $$ SELECT public.reactivate_member('00000000-0000-0000-0000-0000000000bb') $$,
  'Admin reactivates target1'
);

SELECT is(
  (SELECT COUNT(*) FROM public.system_audit_log
    WHERE event_type = 'MEMBER_REACTIVATED' AND organization_id = '00000000-0000-0000-0000-000000000bb1'),
  1::bigint,
  'MEMBER_REACTIVATED event logged exactly once'
);

-- Test 3: update_member_role logs MEMBER_ROLE_CHANGED with previous/new role
SELECT lives_ok(
  $$ SELECT public.update_member_role('00000000-0000-0000-0000-0000000000bb', 'AUDITOR') $$,
  'Admin changes target1 legacy role to AUDITOR'
);

SELECT is(
  (SELECT payload ->> 'previous_role' FROM public.system_audit_log
    WHERE event_type = 'MEMBER_ROLE_CHANGED' AND organization_id = '00000000-0000-0000-0000-000000000bb1'),
  'OPERATOR',
  'MEMBER_ROLE_CHANGED captures previous_role'
);

SELECT is(
  (SELECT payload ->> 'new_role' FROM public.system_audit_log
    WHERE event_type = 'MEMBER_ROLE_CHANGED' AND organization_id = '00000000-0000-0000-0000-000000000bb1'),
  'AUDITOR',
  'MEMBER_ROLE_CHANGED captures new_role'
);

-- Test 4: remove_member — QA BLOCKER-3 (pre-DELETE state must survive in the audit row)
SELECT lives_ok(
  $$ SELECT public.remove_member('00000000-0000-0000-0000-0000000000bb') $$,
  'Admin removes target1'
);

SELECT is(
  (SELECT COUNT(*) FROM public.user_roles WHERE user_id = '00000000-0000-0000-0000-0000000000bb'),
  0::bigint,
  'target1 user_roles row no longer exists after remove_member (hard delete)'
);

SELECT is(
  (SELECT payload ->> 'target_email' FROM public.system_audit_log
    WHERE event_type = 'MEMBER_REMOVED' AND organization_id = '00000000-0000-0000-0000-000000000bb1'),
  'target1@gov.test',
  'MEMBER_REMOVED audit row preserves target_email despite the hard DELETE (INV-3)'
);

-- Test 5: QA BLOCKER-2 — system-only events must never leak through the allowlist
INSERT INTO public.system_audit_log (event_type, severity, payload, source, organization_id)
VALUES (
  'ORGANIZATION_CREATE', 'info',
  jsonb_build_object('legal_name', 'Should not leak to tenant viewers'),
  'super_admin_rpc', '00000000-0000-0000-0000-000000000bb1'
);

SELECT is(
  (SELECT COUNT(*) FROM public.get_tenant_governance_log(200, NULL, NULL, NULL) WHERE event_type = 'ORGANIZATION_CREATE'),
  0::bigint,
  'get_tenant_governance_log excludes system-only event types even for a matching organization_id'
);

-- Test 6: Auditor persona (roles:read only, no roles:manage, no '*') can read the log
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000bc","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000bb1","role":"AUDITOR","permissions":["roles:read"]}}';

SELECT lives_ok(
  $$ SELECT * FROM public.get_tenant_governance_log(50, NULL, NULL, NULL) $$,
  'Auditor holding only roles:read can read the governance log'
);

SELECT ok(
  (SELECT COUNT(*) FROM public.get_tenant_governance_log(200, NULL, NULL, NULL)) >= 4,
  'Auditor sees the logged member-lifecycle events for their own org'
);

-- Test 7: Operador without roles:read/roles:manage is denied (least-privilege)
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000bd","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000bb1","role":"OPERATOR","permissions":[]}}';

SELECT throws_ok(
  $$ SELECT * FROM public.get_tenant_governance_log(50, NULL, NULL, NULL) $$,
  '42501',
  'Unauthorized',
  'Operador without roles:read/roles:manage is denied access to the governance log'
);

-- Test 8: QA BLOCKER-2 / INV-22 — cross-tenant isolation
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000be","app_metadata":{"org_id":"00000000-0000-0000-0000-000000000bb2","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT is(
  (SELECT COUNT(*) FROM public.get_tenant_governance_log(200, NULL, NULL, NULL)),
  0::bigint,
  'Org 2 admin sees zero rows from Org 1''s governance log (tenant isolation)'
);

-- Test 9: QA BLOCKER-1 — dead SELECT policy removed
SELECT is(
  (SELECT COUNT(*) FROM pg_policies WHERE tablename = 'system_audit_log' AND policyname = 'system_audit_log_select_admin_policy'),
  0::bigint,
  'Dead system_audit_log_select_admin_policy has been dropped'
);

SELECT * FROM finish();
ROLLBACK;
