-- =============================================================================
-- pgTAP: RBAC route-guard audit sink (Pilar 3) — migration 20260912000002
-- =============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000009f2', 'RBAC Guard Org', 'RBAC Guard SA',
   '0000000000hg1', 'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000,
   300, 15, 'rbac-guard@test.com', 'EXT_RBAC_GUARD', 'LOGISTICS',
   ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- ── Grants (F1 parity: authenticated + service_role, never anon) ─────────────
SELECT ok(has_function_privilege('authenticated',
  'public.log_access_denied(text,text)', 'EXECUTE'),
  'authenticated can EXECUTE log_access_denied');
SELECT ok(has_function_privilege('service_role',
  'public.log_access_denied(text,text)', 'EXECUTE'),
  'service_role can EXECUTE log_access_denied');
SELECT ok(NOT has_function_privilege('anon',
  'public.log_access_denied(text,text)', 'EXECUTE'),
  'anon cannot EXECUTE log_access_denied (client-only sink)');

-- ── Authenticated caller writes a bound ACCESS_DENIED row ────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000009f9","organization_id":"00000000-0000-0000-0000-0000000009f2","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000009f2","role":"OPERATOR","permissions":["telemetry:read"]}}';

SELECT lives_ok(
  $$ SELECT public.log_access_denied('/admin/financial-impact', 'financial:read') $$,
  'operator lacking financial:read logs an ACCESS_DENIED entry');

RESET ROLE;

-- Verify the trail (post-RESET so the SELECT is not gated by RLS).
SELECT is(
  (SELECT count(*)::int FROM public.system_audit_log
    WHERE event_type = 'ACCESS_DENIED'
      AND organization_id = '00000000-0000-0000-0000-0000000009f2'
      AND severity = 'warning'),
  1,
  'exactly one warning-severity ACCESS_DENIED row bound to the caller org');

SELECT is(
  (SELECT payload ->> 'required' FROM public.system_audit_log
    WHERE event_type = 'ACCESS_DENIED'
      AND organization_id = '00000000-0000-0000-0000-0000000009f2'),
  'financial:read',
  'payload carries the required permission that was missing');

SELECT is(
  (SELECT payload ->> 'actor_id' FROM public.system_audit_log
    WHERE event_type = 'ACCESS_DENIED'
      AND organization_id = '00000000-0000-0000-0000-0000000009f2'),
  '00000000-0000-0000-0000-0000000009f9',
  'actor id is sealed from the verified sub claim, not client-supplied');

SELECT * FROM finish();
ROLLBACK;
