BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- =============================================================================
-- pgTAP: dispute_portal_tokens — Forensic Dispute Portal (Item 5.3)
-- Tests: P1–P14 from council test plan + structural + grant tests.
-- =============================================================================

-- ── Seeds (as postgres: bypasses RLS/grants for fixture setup) ───────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-000000dad001', 'Org Portal', 'Org Portal SA', '00000000dad001',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'portal@test.com', 'EXT_PORTAL', 'LOGISTICS', ARRAY['test.com']),
  ('00000000-0000-0000-0000-000000dad002', 'Org Other', 'Org Other SA', '00000000dad002',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'other@test.com', 'EXT_OTHER', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Disputed queue (happy path) + non-disputed (state gate).
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('00000000-0000-0000-0000-000000dad0e1', '00000000-0000-0000-0000-000000dad001',
   '00000000-0000-0000-0000-000000dad0f1', 'set-portal',
   '00000000-0000-0000-0000-000000dad0aa',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Exceeded tolerance","fine_cents":50000}'::jsonb,
   'disputed', NOW(), '00000000-0000-0000-0000-000000dad0b1',
   NOW() + INTERVAL '5 days'),
  ('00000000-0000-0000-0000-000000dad0e2', '00000000-0000-0000-0000-000000dad001',
   '00000000-0000-0000-0000-000000dad0f2', 'set-portal',
   '00000000-0000-0000-0000-000000dad0aa', '{}'::jsonb, 'pending',
   NULL, NULL, NULL)
ON CONFLICT (id) DO NOTHING;

-- Evidence attachment for the disputed queue (for read_dispute_portal response).
INSERT INTO public.dispute_evidence_attachments
  (id, organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, verification_status, uploaded_by, attached_at)
VALUES
  ('00000000-0000-0000-0000-000000dad0a1', '00000000-0000-0000-0000-000000dad001',
   '00000000-0000-0000-0000-000000dad0e1',
   '00000000-0000-0000-0000-000000dad001/00000000-0000-0000-0000-000000dad0e1/photo1.jpg',
   'photo1.jpg', 'image/jpeg', 2048,
   'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
   'VERIFIED', '00000000-0000-0000-0000-000000dad0b1', '2026-08-13T12:00:00Z')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- STRUCTURAL + GRANT TESTS
-- =============================================================================

-- S1: Table exists
SELECT has_table('public', 'dispute_portal_tokens', 'dispute_portal_tokens table exists');

-- S2: RLS enabled
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE relname = 'dispute_portal_tokens'),
  'RLS is enabled on dispute_portal_tokens');

-- S3: generate function exists
SELECT has_function(
  'public', 'generate_dispute_portal_token',
  ARRAY['uuid', 'uuid', 'uuid', 'integer', 'integer'],
  'generate_dispute_portal_token exists with expected signature');

-- S4: read function exists
SELECT has_function(
  'public', 'read_dispute_portal',
  ARRAY['uuid'],
  'read_dispute_portal exists with expected signature');

-- S5: generate is SECURITY DEFINER
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'generate_dispute_portal_token'),
  true, 'generate_dispute_portal_token is SECURITY DEFINER');

-- S6: read is SECURITY DEFINER
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'read_dispute_portal'),
  true, 'read_dispute_portal is SECURITY DEFINER');

-- P1: anon direct SELECT → blocked. Deny-all is enforced by REVOKE (no table
-- grant), which raises 42501 *before* RLS evaluates — stronger than a 0-row RLS.
SET LOCAL ROLE anon;
SELECT throws_ok(
  $$ SELECT count(*) FROM public.dispute_portal_tokens $$,
  '42501', NULL,
  'P1: anon direct SELECT denied (deny-all: no table grant)');
RESET ROLE;

-- P2: authenticated direct SELECT → blocked (same deny-all REVOKE).
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000dad0b1","app_metadata":{"org_id":"00000000-0000-0000-0000-000000dad001","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT count(*) FROM public.dispute_portal_tokens $$,
  '42501', NULL,
  'P2: authenticated direct SELECT denied (deny-all: no table grant)');
RESET ROLE;

-- =============================================================================
-- GENERATE TOKEN TESTS
-- =============================================================================

-- P3: Generate for non-disputed queue → 42501
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000dad0b1","app_metadata":{"org_id":"00000000-0000-0000-0000-000000dad001","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT public.generate_dispute_portal_token(
       '00000000-0000-0000-0000-000000dad001',
       '00000000-0000-0000-0000-000000dad0e2',
       '00000000-0000-0000-0000-000000dad0b1'
     ) $$,
  '42501', NULL,
  'P3: generate for non-disputed queue rejected with 42501');
RESET ROLE;

-- P4: Generate cross-org → 42501
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000dad0b1","app_metadata":{"org_id":"00000000-0000-0000-0000-000000dad002","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT public.generate_dispute_portal_token(
       '00000000-0000-0000-0000-000000dad001',
       '00000000-0000-0000-0000-000000dad0e1',
       '00000000-0000-0000-0000-000000dad0b1'
     ) $$,
  '42501', NULL,
  'P4: cross-org generate rejected with 42501 (INV-22)');
RESET ROLE;

-- Happy path: generate a valid token
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000dad0b1","app_metadata":{"org_id":"00000000-0000-0000-0000-000000dad001","role":"TENANT_ADMIN"}}';
SELECT lives_ok(
  $$ SELECT public.generate_dispute_portal_token(
       '00000000-0000-0000-0000-000000dad001',
       '00000000-0000-0000-0000-000000dad0e1',
       '00000000-0000-0000-0000-000000dad0b1',
       24, 3
     ) $$,
  'Happy path: generate_dispute_portal_token succeeds for TENANT_ADMIN');
RESET ROLE;

-- P12: Ledger fact DISPUTE_PORTAL_TOKEN_GENERATED logged
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-000000dad001'
      AND type = 'DISPUTE_PORTAL_TOKEN_GENERATED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-000000dad0e1'),
  1, 'P12: DISPUTE_PORTAL_TOKEN_GENERATED ledger fact logged on generation');

-- =============================================================================
-- READ PORTAL TESTS (using the generated token)
-- =============================================================================

-- Capture the generated token + id as postgres (deny-all base table is
-- unreadable by authenticated) into a temp table. Grant the temp table to
-- authenticated so the revoke test can resolve the token id by PK without
-- touching the sealed base table from the outer (authenticated) query.
CREATE TEMP TABLE _test_token AS
  SELECT id, token FROM public.dispute_portal_tokens
   WHERE organization_id = '00000000-0000-0000-0000-000000dad001'
     AND queue_entry_id = '00000000-0000-0000-0000-000000dad0e1'
   LIMIT 1;
GRANT SELECT ON _test_token TO authenticated;

-- P8: read_dispute_portal valid → JSONB with evidence
SELECT ok(
  (SELECT read_dispute_portal(token) IS NOT NULL FROM _test_token),
  'P8: read_dispute_portal returns non-null JSONB for valid token');

-- P9: access_count incremented to 1
SELECT is(
  (SELECT access_count FROM public.dispute_portal_tokens
    WHERE organization_id = '00000000-0000-0000-0000-000000dad001'
      AND queue_entry_id = '00000000-0000-0000-0000-000000dad0e1'
    LIMIT 1),
  1, 'P9: access_count incremented to 1 after first read');

-- P14: response excludes fine_cents (Business amendment)
SELECT ok(
  NOT (
    (SELECT read_dispute_portal(token)::text FROM _test_token) LIKE '%fine_cents%'
  ),
  'P14: portal response does NOT contain fine_cents');

-- Exhaust the remaining access (total = 3 = max_access_count).
-- Already at count=2 after P8 + P14. Need 1 more to hit 3.
SELECT read_dispute_portal(token) FROM _test_token;

-- P7: exhausted count → error
SELECT throws_ok(
  $$ SELECT read_dispute_portal(token) FROM _test_token $$,
  '42501', NULL,
  'P7: read_dispute_portal with exhausted count rejected with 42501');

-- P5: expired token → error
-- Disable immutability trigger to manipulate sealed fields for test setup.
-- Shift created_at back too: chk_dpt_expires_window (expires > created_at) is a
-- CHECK constraint, not the trigger, so the expiry must still post-date creation.
ALTER TABLE public.dispute_portal_tokens DISABLE TRIGGER trg_dpt_no_immutable_update;
UPDATE public.dispute_portal_tokens
   SET created_at_utc = NOW() - INTERVAL '2 hours',
       expires_at_utc = NOW() - INTERVAL '1 hour',
       access_count = 0
 WHERE organization_id = '00000000-0000-0000-0000-000000dad001'
   AND queue_entry_id = '00000000-0000-0000-0000-000000dad0e1';
ALTER TABLE public.dispute_portal_tokens ENABLE TRIGGER trg_dpt_no_immutable_update;

SELECT throws_ok(
  $$ SELECT read_dispute_portal(token) FROM _test_token $$,
  '42501', NULL,
  'P5: read_dispute_portal with expired token rejected with 42501');

-- Restore expiry for revocation test.
ALTER TABLE public.dispute_portal_tokens DISABLE TRIGGER trg_dpt_no_immutable_update;
UPDATE public.dispute_portal_tokens
   SET expires_at_utc = NOW() + INTERVAL '24 hours'
 WHERE organization_id = '00000000-0000-0000-0000-000000dad001'
   AND queue_entry_id = '00000000-0000-0000-0000-000000dad0e1';
ALTER TABLE public.dispute_portal_tokens ENABLE TRIGGER trg_dpt_no_immutable_update;

-- =============================================================================
-- REVOKE + P6 TESTS
-- =============================================================================

-- P13: revoke_dispute_portal_token stamps + logs fact
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-000000dad0b1","app_metadata":{"org_id":"00000000-0000-0000-0000-000000dad001","role":"TENANT_ADMIN"}}';
SELECT lives_ok(
  $$ SELECT public.revoke_dispute_portal_token(
       '00000000-0000-0000-0000-000000dad001',
       (SELECT id FROM _test_token)
     ) $$,
  'P13a: revoke_dispute_portal_token succeeds');
RESET ROLE;

SELECT isnt(
  (SELECT revoked_at_utc FROM public.dispute_portal_tokens
    WHERE organization_id = '00000000-0000-0000-0000-000000dad001'
      AND queue_entry_id = '00000000-0000-0000-0000-000000dad0e1'
    LIMIT 1),
  NULL::timestamptz,
  'P13b: revoked_at_utc is NOT NULL after revocation');

-- P6: read with revoked token → error
SELECT throws_ok(
  $$ SELECT read_dispute_portal(token) FROM _test_token $$,
  '42501', NULL,
  'P6: read_dispute_portal with revoked token rejected with 42501');

-- =============================================================================
-- IMMUTABILITY + DELETE TESTS
-- =============================================================================

-- P10: immutability trigger blocks sealed field mutation
SELECT throws_ok(
  $$ UPDATE public.dispute_portal_tokens
        SET token = gen_random_uuid()
      WHERE organization_id = '00000000-0000-0000-0000-000000dad001' $$,
  '23001', NULL,
  'P10: immutability trigger blocks token field mutation');

-- P11: DELETE blocked
SELECT throws_ok(
  $$ DELETE FROM public.dispute_portal_tokens
      WHERE organization_id = '00000000-0000-0000-0000-000000dad001' $$,
  '23001', NULL,
  'P11: DELETE blocked on append-only table');

SELECT * FROM finish();
ROLLBACK;
