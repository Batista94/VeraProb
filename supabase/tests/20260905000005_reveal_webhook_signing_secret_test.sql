-- pgTAP: reveal-webhook-signing-secret — Zero-Trust Provisioning (P1)
--
-- Verifica:
--   CT01: TENANT_ADMIN da org correta pode ler webhook_signing_keys (RLS pass)
--   CT02: role OPERATOR é bloqueado pelo RLS (0 rows — INV-22)
--   CT03: TENANT_ADMIN de outra org recebe 0 rows (tenant isolation — INV-22)
--   CT04: audit log WEBHOOK_SECRET_REVEALED inserível via service_role (simula edge fn)
--   CT05: audit log WEBHOOK_SECRET_ROTATED inserível via service_role
--   CT06: provision cria chave active idempotente (UNIQUE partial index)
--   CT07: índice forense de webhook_secret existe
--
-- Run: make test-db

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

-- ── Seeds ─────────────────────────────────────────────────────────────────────

-- Org A: TENANT_ADMIN que vai operar
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-f10700000001',
  'P1 Reveal Org A', 'P1 Reveal A SA', '00000000000101',
  'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
  'a@p1reveal.com', 'EXT_P1_A', 'LOGISTICS', ARRAY['p1reveal.com']
) ON CONFLICT (id) DO NOTHING;

-- Org B: TENANT_ADMIN diferente (cross-org isolation)
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-f10700000002',
  'P1 Reveal Org B', 'P1 Reveal B SA', '00000000000201',
  'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 10000, 300, 15,
  'b@p1reveal.com', 'EXT_P1_B', 'LOGISTICS', ARRAY['p1reveal.com']
) ON CONFLICT (id) DO NOTHING;

-- Chave active para Org A (simula provision já realizado).
INSERT INTO public.webhook_signing_keys (id, organization_id, version, status)
VALUES ('00000000-0000-0000-0000-f10700000010', '00000000-0000-0000-0000-f10700000001', 1, 'active')
ON CONFLICT DO NOTHING;

-- ── CT01: TENANT_ADMIN da org correta pode ler (RLS pass) ────────────────────

SET LOCAL role TO authenticated;
SET LOCAL "request.jwt.claims" TO
  '{"sub":"user-p1-a","app_metadata":{"org_id":"00000000-0000-0000-0000-f10700000001","role":"TENANT_ADMIN"}}';

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.webhook_signing_keys
     WHERE organization_id = '00000000-0000-0000-0000-f10700000001'::uuid $$,
  $$ VALUES (1) $$,
  'CT01: TENANT_ADMIN org A lê sua própria chave (RLS pass)'
);

-- ── CT02: OPERATOR é bloqueado (0 rows — INV-22) ─────────────────────────────

SET LOCAL "request.jwt.claims" TO
  '{"sub":"user-p1-op","app_metadata":{"org_id":"00000000-0000-0000-0000-f10700000001","role":"OPERATOR"}}';

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.webhook_signing_keys
     WHERE organization_id = '00000000-0000-0000-0000-f10700000001'::uuid $$,
  $$ VALUES (0) $$,
  'CT02: OPERATOR não tem acesso a webhook_signing_keys (RLS block)'
);

-- ── CT03: TENANT_ADMIN de outra org → 0 rows (cross-org isolation — INV-22) ──

SET LOCAL "request.jwt.claims" TO
  '{"sub":"user-p1-b","app_metadata":{"org_id":"00000000-0000-0000-0000-f10700000002","role":"TENANT_ADMIN"}}';

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.webhook_signing_keys
     WHERE organization_id = '00000000-0000-0000-0000-f10700000001'::uuid $$,
  $$ VALUES (0) $$,
  'CT03: TENANT_ADMIN org B não vê chaves de org A (tenant isolation)'
);

-- ── CT04: audit log WEBHOOK_SECRET_REVEALED via service_role ─────────────────

SET LOCAL role TO service_role;
-- service_role bypassa RLS (comportamento padrão Supabase).

SELECT lives_ok(
  $$ INSERT INTO public.system_audit_log (event_type, severity, source, organization_id, payload)
     VALUES ('WEBHOOK_SECRET_REVEALED', 'info', 'edge_function',
             '00000000-0000-0000-0000-f10700000001',
             '{"key_version":1,"action":"provision","user_id":"user-p1-a"}') $$,
  'CT04: service_role insere WEBHOOK_SECRET_REVEALED no audit log'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.system_audit_log
     WHERE event_type = 'WEBHOOK_SECRET_REVEALED'
       AND organization_id = '00000000-0000-0000-0000-f10700000001'::uuid $$,
  $$ VALUES (1) $$,
  'CT04b: audit row WEBHOOK_SECRET_REVEALED presente no log'
);

-- ── CT05: audit log WEBHOOK_SECRET_ROTATED via service_role ──────────────────

SELECT lives_ok(
  $$ INSERT INTO public.system_audit_log (event_type, severity, source, organization_id, payload)
     VALUES ('WEBHOOK_SECRET_ROTATED', 'info', 'edge_function',
             '00000000-0000-0000-0000-f10700000001',
             '{"previous_version":1,"new_version":2,"action":"rotate","user_id":"user-p1-a"}') $$,
  'CT05: service_role insere WEBHOOK_SECRET_ROTATED no audit log'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.system_audit_log
     WHERE event_type = 'WEBHOOK_SECRET_ROTATED'
       AND organization_id = '00000000-0000-0000-0000-f10700000001'::uuid $$,
  $$ VALUES (1) $$,
  'CT05b: audit row WEBHOOK_SECRET_ROTATED presente no log'
);

-- ── CT06: UNIQUE partial index — não permite 2 chaves active para mesma org ───
-- Run as postgres (table owner): service_role only has SELECT on this table
-- (INV-31 edge-only writes via authenticated TENANT_ADMIN / SECURITY DEFINER).
RESET ROLE;

SELECT throws_ok(
  $$ INSERT INTO public.webhook_signing_keys (organization_id, version, status)
     VALUES ('00000000-0000-0000-0000-f10700000001', 2, 'active') $$,
  '23505',
  NULL,
  'CT06: UNIQUE partial index bloqueia 2ª chave active na mesma org'
);

-- Retiring é permitido (mesmo org, outra status).
SELECT lives_ok(
  $$ INSERT INTO public.webhook_signing_keys (organization_id, version, status)
     VALUES ('00000000-0000-0000-0000-f10700000001', 2, 'retiring') $$,
  'CT06b: chave retiring pode coexistir com active na mesma org'
);

-- ── CT07: índice forense de webhook_secret existe ─────────────────────────────

SELECT has_index(
  'public',
  'system_audit_log',
  'idx_system_audit_log_webhook_secret',
  'CT07: idx_system_audit_log_webhook_secret existe para lookup forense'
);

-- Finish
SELECT * FROM finish();
ROLLBACK;
