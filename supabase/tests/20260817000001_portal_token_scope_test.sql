BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- =============================================================================
-- pgTAP: portal_token_scope — Sprint A M1
-- Covers: scope/cap columns, sealing, generate_portal_submit_token (TENANT_ADMIN
-- only + disputed gate), and the widened read precondition (applied|disputed).
-- =============================================================================

-- ── Seeds (as postgres: bypasses RLS/grants for fixture setup) ───────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-00000dad1a01', 'Org Scope', 'Org Scope SA', '00000000dad1a1',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'scope@test.com', 'EXT_SCOPE', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-00000dad1a02', 'Org Other', 'Org Other SA', '00000000dad1a2',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'other2@test.com', 'EXT_OTHER2', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Disputed (submit gate ok), applied (read widening), pending (gate fail).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-00000dad1e01', '00000000-0000-0000-0000-00000dad1a01',
   '00000000-0000-0000-0000-00000dad1f01', 'set-scope',
   '00000000-0000-0000-0000-00000dad1aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Exceeded","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-00000dad1b01', NOW() + INTERVAL '5 days'),
  ('00000000-0000-0000-0000-00000dad1e03', '00000000-0000-0000-0000-00000dad1a01',
   '00000000-0000-0000-0000-00000dad1f03', 'set-scope',
   '00000000-0000-0000-0000-00000dad1aa1',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Applied"}'::jsonb,
   'applied', NULL, NULL, NULL),
  ('00000000-0000-0000-0000-00000dad1e02', '00000000-0000-0000-0000-00000dad1a01',
   '00000000-0000-0000-0000-00000dad1f02', 'set-scope',
   '00000000-0000-0000-0000-00000dad1aa1', '{}'::jsonb, 'pending',
   NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- STRUCTURAL TESTS
-- =============================================================================

-- S1: token_scope column exists
SELECT has_column('public', 'dispute_portal_tokens', 'token_scope',
  'S1: token_scope column exists');

-- S2: max_submissions column exists
SELECT has_column('public', 'dispute_portal_tokens', 'max_submissions',
  'S2: max_submissions column exists');

-- S3: token_scope is NOT NULL (information_schema — local pgTAP lacks 4-arg overload)
SELECT ok(
  (SELECT is_nullable = 'NO' FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'dispute_portal_tokens'
      AND column_name = 'token_scope'),
  'S3: token_scope is NOT NULL');

-- S3b: token_scope default is 'read'
SELECT ok(
  (SELECT column_default LIKE '%read%' FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'dispute_portal_tokens'
      AND column_name = 'token_scope'),
  'S3b: token_scope default is read');

-- S4: generate_portal_submit_token exists with expected signature
SELECT has_function(
  'public', 'generate_portal_submit_token',
  ARRAY['uuid', 'uuid', 'uuid', 'integer', 'integer', 'integer'],
  'S4: generate_portal_submit_token exists with expected signature');

-- S5: generate_portal_submit_token is SECURITY DEFINER
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'generate_portal_submit_token'),
  true, 'S5: generate_portal_submit_token is SECURITY DEFINER');

-- S6: chk_dpt_scope rejects an invalid scope (direct insert as postgres)
SELECT throws_ok(
  $$ INSERT INTO public.dispute_portal_tokens
       (organization_id, queue_entry_id, created_by_user_id, expires_at_utc, token_scope)
     VALUES ('00000000-0000-0000-0000-00000dad1a01',
             '00000000-0000-0000-0000-00000dad1e01',
             '00000000-0000-0000-0000-00000dad1b01',
             NOW() + INTERVAL '1 hour', 'bogus') $$,
  '23514', NULL,
  'S6: chk_dpt_scope rejects invalid token_scope');

-- S7: chk_dpt_max_sub rejects out-of-range submission cap
SELECT throws_ok(
  $$ INSERT INTO public.dispute_portal_tokens
       (organization_id, queue_entry_id, created_by_user_id, expires_at_utc, max_submissions)
     VALUES ('00000000-0000-0000-0000-00000dad1a01',
             '00000000-0000-0000-0000-00000dad1e01',
             '00000000-0000-0000-0000-00000dad1b01',
             NOW() + INTERVAL '1 hour', 0) $$,
  '23514', NULL,
  'S7: chk_dpt_max_sub rejects max_submissions out of [1,20]');

-- =============================================================================
-- generate_portal_submit_token BEHAVIOR
-- =============================================================================

-- B1: submit token for non-disputed queue → 42501
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad1b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad1a01","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT public.generate_portal_submit_token(
       '00000000-0000-0000-0000-00000dad1a01',
       '00000000-0000-0000-0000-00000dad1e02',
       '00000000-0000-0000-0000-00000dad1b01') $$,
  '42501', NULL,
  'B1: submit token for non-disputed queue rejected (42501)');
RESET ROLE;

-- B2: submit token cross-org → 42501 (INV-22/26)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad1b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad1a02","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT public.generate_portal_submit_token(
       '00000000-0000-0000-0000-00000dad1a01',
       '00000000-0000-0000-0000-00000dad1e01',
       '00000000-0000-0000-0000-00000dad1b01') $$,
  '42501', NULL,
  'B2: cross-org submit token rejected (42501)');
RESET ROLE;

-- B3: submit token as AUDITOR → 42501 (TENANT_ADMIN only; submit > read)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad1b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad1a01","role":"AUDITOR"}}';
SELECT throws_ok(
  $$ SELECT public.generate_portal_submit_token(
       '00000000-0000-0000-0000-00000dad1a01',
       '00000000-0000-0000-0000-00000dad1e01',
       '00000000-0000-0000-0000-00000dad1b01') $$,
  '42501', NULL,
  'B3: AUDITOR cannot mint a submit token (42501)');
RESET ROLE;

-- HP: TENANT_ADMIN mints a submit token → lives_ok
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad1b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad1a01","role":"TENANT_ADMIN"}}';
SELECT lives_ok(
  $$ SELECT public.generate_portal_submit_token(
       '00000000-0000-0000-0000-00000dad1a01',
       '00000000-0000-0000-0000-00000dad1e01',
       '00000000-0000-0000-0000-00000dad1b01',
       24, 5, 7) $$,
  'HP: TENANT_ADMIN mints submit token for disputed queue');
RESET ROLE;

-- V1: minted token has token_scope='submit'
SELECT is(
  (SELECT token_scope FROM public.dispute_portal_tokens
    WHERE organization_id = '00000000-0000-0000-0000-00000dad1a01'
      AND queue_entry_id = '00000000-0000-0000-0000-00000dad1e01'
      AND token_scope = 'submit' LIMIT 1),
  'submit', 'V1: minted token carries token_scope = submit');

-- V2: max_submissions persisted from the parameter
SELECT is(
  (SELECT max_submissions FROM public.dispute_portal_tokens
    WHERE organization_id = '00000000-0000-0000-0000-00000dad1a01'
      AND queue_entry_id = '00000000-0000-0000-0000-00000dad1e01'
      AND token_scope = 'submit' LIMIT 1),
  7, 'V2: max_submissions persisted from parameter');

-- L1: ledger fact logged with token_scope = submit
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-00000dad1a01'
      AND type = 'DISPUTE_PORTAL_TOKEN_GENERATED'
      AND payload->>'token_scope' = 'submit'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-00000dad1e01'),
  1, 'L1: DISPUTE_PORTAL_TOKEN_GENERATED (submit) ledger fact logged (INV-3)');

-- IM: token_scope is sealed — mutation blocked by immutability trigger
SELECT throws_ok(
  $$ UPDATE public.dispute_portal_tokens
        SET token_scope = 'read'
      WHERE organization_id = '00000000-0000-0000-0000-00000dad1a01'
        AND token_scope = 'submit' $$,
  '23001', NULL,
  'IM: token_scope sealed — mutation blocked (INV-3)');

-- =============================================================================
-- READ PRECONDITION WIDENING
-- =============================================================================

-- W1: read token issuable for an APPLIED sanction (De Acordo precondition)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000dad1b01","app_metadata":{"org_id":"00000000-0000-0000-0000-00000dad1a01","role":"TENANT_ADMIN"}}';
SELECT lives_ok(
  $$ SELECT public.generate_dispute_portal_token(
       '00000000-0000-0000-0000-00000dad1a01',
       '00000000-0000-0000-0000-00000dad1e03',
       '00000000-0000-0000-0000-00000dad1b01') $$,
  'W1: read token issuable for applied sanction (widened precondition)');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
