-- =============================================================================
-- pgTAP: Live-check O(1) + Four-Eyes success/self-approval (Pilar 1.5)
-- Migration: 20260910000001_tenant_rbac_live_check
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- ── Fixture ───────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-000000001001',
  'Live-Check Org', 'Live-Check Org SA', '00000000000010',
  'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
  'lc@test.com', 'EXT_LC', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

-- Custom role containing sla:approve (sensitive).
INSERT INTO public.tenant_roles (id, organization_id, name, is_system) VALUES
  ('00000000-0000-0000-0000-000000001090',
   '00000000-0000-0000-0000-000000001001',
   'LC-Approver', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key) VALUES
  ('00000000-0000-0000-0000-000000001090', 'sla:approve')
ON CONFLICT DO NOTHING;

-- stale_user (sub=1013) has a REVOKED grant — stale JWT will carry sla:approve.
INSERT INTO public.user_tenant_roles (
  user_id, tenant_role_id, organization_id, granted_by, revoked_at
) VALUES (
  '00000000-0000-0000-0000-000000001013',
  '00000000-0000-0000-0000-000000001090',
  '00000000-0000-0000-0000-000000001001',
  '00000000-0000-0000-0000-000000001011',
  NOW()
) ON CONFLICT DO NOTHING;

-- ── 1. Helper function exists ─────────────────────────────────────────────────
SELECT has_function(
  'public', '_rbac_live_check_permission', ARRAY['text'],
  '_rbac_live_check_permission(text) helper registered');

-- ── 2. Four-Eyes: admin1 enqueues PENDING request ─────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000001011","organization_id":"00000000-0000-0000-0000-000000001001","app_metadata":{"org_id":"00000000-0000-0000-0000-000000001001","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.create_tenant_role(
       'LC-Finance-Export',
       'four-eyes test role',
       '[{"key":"financial:export"}]'::jsonb
     ) $$,
  'sensitive create_tenant_role enqueues PENDING request');

-- ── 3. admin2 approves the pending request ────────────────────────────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000001012","organization_id":"00000000-0000-0000-0000-000000001001","app_metadata":{"org_id":"00000000-0000-0000-0000-000000001001","role":"TENANT_ADMIN","permissions":["*"]}}';

SELECT lives_ok(
  $$ SELECT public.approve_role_change(
       (SELECT id FROM public.role_change_requests
         WHERE request_type = 'CREATE_ROLE'
           AND organization_id = '00000000-0000-0000-0000-000000001001'
         ORDER BY created_at DESC LIMIT 1)
     ) $$,
  'second admin can approve a four-eyes request (success path)');

-- ── 4. admin2 enqueues own request ────────────────────────────────────────────
SELECT lives_ok(
  $$ SELECT public.create_tenant_role(
       'LC-Self-Approve-Bait',
       'self-approve test',
       '[{"key":"financial:export"}]'::jsonb
     ) $$,
  'admin2 enqueues a second PENDING request');

-- ── 5. Self-approval blocked ──────────────────────────────────────────────────
SELECT throws_ok(
  $$ SELECT public.approve_role_change(
       (SELECT id FROM public.role_change_requests
         WHERE request_type = 'CREATE_ROLE'
           AND organization_id = '00000000-0000-0000-0000-000000001001'
           AND status = 'PENDING'
         ORDER BY created_at DESC LIMIT 1)
     ) $$,
  'P0001',
  'Self-approval is not permitted',
  'requester (admin2) blocked from self-approving their own request');

-- ── 6-7. Live-check: stale token blocked by 42501 ────────────────────────────
-- stale_user (sub=1013): AUDITOR + sla:approve in JWT but grant is revoked in DB.
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000001013","organization_id":"00000000-0000-0000-0000-000000001001","app_metadata":{"org_id":"00000000-0000-0000-0000-000000001001","role":"AUDITOR","permissions":["sla:approve"]}}';

SELECT throws_ok(
  $$ SELECT public.approve_sanction(
       '00000000-0000-0000-0000-000000001001',
       gen_random_uuid(),
       '00000000-0000-0000-0000-000000001013',
       'stale@test.com',
       NOW()
     ) $$,
  '42501',
  'Permission revoked or insufficient',
  'stale custom sla:approve blocked by live-check in approve_sanction');

SELECT throws_ok(
  $$ SELECT public.reject_sanction(
       '00000000-0000-0000-0000-000000001001',
       gen_random_uuid(),
       '00000000-0000-0000-0000-000000001013',
       'stale@test.com',
       'reason text',
       'SLA_BREACH',
       NOW()
     ) $$,
  '42501',
  'Permission revoked or insufficient',
  'stale custom sla:approve blocked by live-check in reject_sanction');

-- ── Reset role BEFORE querying system_audit_log (no SELECT grant to authenticated)
RESET ROLE;

-- ── 8. Approved request status ────────────────────────────────────────────────
SELECT is(
  (SELECT status FROM public.role_change_requests
    WHERE request_type = 'CREATE_ROLE'
      AND organization_id = '00000000-0000-0000-0000-000000001001'
      AND status = 'APPROVED'
    LIMIT 1),
  'APPROVED',
  'approved request status = APPROVED');

-- ── 9. Audit row written ──────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
    WHERE event_type = 'ROLE_CHANGE_APPROVED'
      AND organization_id = '00000000-0000-0000-0000-000000001001'),
  1,
  'ROLE_CHANGE_APPROVED audit row written to system_audit_log');

SELECT * FROM finish();
ROLLBACK;
