BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(48);

-- =============================================================================
-- pgTAP: Legal Gate LGPD (20260922000001) — hardened
-- Happy path · adverse · information security (INV-2/3/22/26, LGPD Art. 8)
-- =============================================================================

-- ── Fixtures ─────────────────────────────────────────────────────────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES (
  '00000000-0000-0000-0000-00000000b001', 'Org Legal', 'Org Legal SA',
  '00000000lgpd01', 'America/Sao_Paulo', 'BRL', 'enterprise', 100, 10, 15000,
  300, 15, 'legal@test.com', 'EXT_LGPD', 'LOGISTICS', ARRAY['test.com']
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.drivers (
  id, full_name, license_number, status, organization_id
) VALUES (
  '00000000-0000-0000-0000-00000000d101',
  'Driver Legal', 'LIC-LGPD-001', 'active',
  '00000000-0000-0000-0000-00000000b001'
) ON CONFLICT (id) DO NOTHING;

-- ── Structure ────────────────────────────────────────────────────────────────
SELECT has_table('public', 'legal_documents', 'S1: legal_documents exists');
SELECT has_table('public', 'user_legal_consents', 'S2: user_legal_consents exists');

-- ── Seed (happy) ─────────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.legal_documents
    WHERE doc_type = 'terms_of_use' AND version = '1.0'
      AND status = 'published' AND active_to_utc IS NULL),
  1, 'SEED1: terms_of_use 1.0 published and active');

SELECT is(
  (SELECT count(*)::int FROM public.legal_documents
    WHERE doc_type = 'telegram_bot_terms' AND version = '1.0'
      AND status = 'published' AND active_to_utc IS NULL),
  1, 'SEED2: telegram_bot_terms 1.0 published and active');

SELECT is(
  (SELECT content_sha256 FROM public.legal_documents
    WHERE doc_type = 'terms_of_use' AND version = '1.0'),
  (SELECT encode(extensions.digest(body_markdown, 'sha256'), 'hex')
     FROM public.legal_documents
    WHERE doc_type = 'terms_of_use' AND version = '1.0'),
  'SEED3: terms content_sha256 matches body digest (Art. 8 proof material)');

-- ── Security: draft leak / grants / append-only ──────────────────────────────
INSERT INTO public.legal_documents (
  id, doc_type, version, title, body_markdown, content_sha256,
  status, published_at_utc, active_to_utc
) VALUES (
  '00000000-0000-0000-0000-00000000d001',
  'privacy_policy', '0.1-draft', 'Draft Privacy', 'draft body',
  repeat('a', 64), 'draft', NULL, NULL
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000a001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000b001","role":"TENANT_ADMIN"}}';

SELECT is(
  (SELECT count(*)::int FROM public.legal_documents
    WHERE id = '00000000-0000-0000-0000-00000000d001'),
  0, 'SEC1: draft document invisible to authenticated (INV-2)');

SELECT ok(
  (SELECT count(*)::int FROM public.legal_documents
    WHERE status = 'published') >= 2,
  'SEC2: authenticated can SELECT published documents');

RESET ROLE;

INSERT INTO public.user_legal_consents (
  id, user_id, document_id, document_version, document_content_sha256, action
)
SELECT
  '00000000-0000-0000-0000-00000000c099',
  '00000000-0000-0000-0000-00000000a099',
  id, version, content_sha256, 'accepted'
FROM public.legal_documents
WHERE doc_type = 'terms_of_use' AND version = '1.0'
LIMIT 1;

SELECT throws_ok(
  $$ UPDATE public.user_legal_consents SET user_agent = 'x'
      WHERE id = '00000000-0000-0000-0000-00000000c099' $$,
  '23001', NULL, 'SEC3: UPDATE blocked on user_legal_consents (INV-3)');

SELECT throws_ok(
  $$ DELETE FROM public.user_legal_consents
      WHERE id = '00000000-0000-0000-0000-00000000c099' $$,
  '23001', NULL, 'SEC4: DELETE blocked on user_legal_consents (INV-3)');

SELECT throws_ok(
  $$ TRUNCATE public.user_legal_consents $$,
  '23001', NULL, 'SEC4b: TRUNCATE blocked on user_legal_consents (INV-3)');

SELECT ok(
  has_table_privilege('authenticated', 'public.legal_documents', 'SELECT'),
  'SEC5: authenticated SELECT legal_documents');
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.legal_documents', 'INSERT'),
  'SEC6: authenticated cannot INSERT legal_documents');
SELECT ok(
  has_table_privilege('authenticated', 'public.user_legal_consents', 'SELECT'),
  'SEC7: authenticated SELECT user_legal_consents');
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.user_legal_consents', 'INSERT'),
  'SEC8: authenticated cannot INSERT user_legal_consents (RPC-only)');

-- Direct client INSERT must fail (privilege), not just RLS absence
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000a001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000b001","role":"TENANT_ADMIN"}}';

SELECT throws_ok(
  $$ INSERT INTO public.user_legal_consents
       (user_id, document_id, document_version, document_content_sha256, action)
     SELECT '00000000-0000-0000-0000-00000000a001', id, version, content_sha256, 'accepted'
       FROM public.legal_documents
      WHERE doc_type = 'terms_of_use' AND active_to_utc IS NULL LIMIT 1 $$,
  '42501', NULL, 'SEC9: direct INSERT by authenticated denied (42501)');

RESET ROLE;

-- ── Happy path: Flutter accept / withdraw / re-accept ────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000a001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000b001","role":"TENANT_ADMIN"}}';

SELECT ok(
  NOT public.has_current_legal_consent('00000000-0000-0000-0000-00000000a001'),
  'HP1: no consent before accept');

SELECT is(
  (SELECT public.get_legal_consent_status() ->> 'status'),
  'pending',
  'HP2: get_legal_consent_status returns pending');

SELECT ok(
  (SELECT public.get_legal_consent_status() -> 'document' ->> 'id') IS NOT NULL,
  'HP3: pending status includes active document payload');

SELECT lives_ok(
  $$ SELECT public.accept_legal_terms(
       (SELECT id FROM public.legal_documents
         WHERE doc_type = 'terms_of_use' AND active_to_utc IS NULL LIMIT 1)
     ) $$,
  'HP4: accept_legal_terms succeeds');

SELECT ok(
  public.has_current_legal_consent('00000000-0000-0000-0000-00000000a001'),
  'HP5: has_current_legal_consent true after accept');

SELECT is(
  (SELECT public.get_legal_consent_status() ->> 'status'),
  'current',
  'HP6: get_legal_consent_status returns current after accept');

-- Consent row stores exact document hash (Art. 8 burden of proof)
SELECT is(
  (SELECT c.document_content_sha256
     FROM public.user_legal_consents c
     JOIN public.legal_documents d ON d.id = c.document_id
    WHERE c.user_id = '00000000-0000-0000-0000-00000000a001'
      AND c.action = 'accepted'
    ORDER BY c.consented_at_utc DESC LIMIT 1),
  (SELECT content_sha256 FROM public.legal_documents
    WHERE doc_type = 'terms_of_use' AND active_to_utc IS NULL LIMIT 1),
  'HP7: consent row stores document_content_sha256 matching active doc');

SELECT is(
  (SELECT public.accept_legal_terms(
     (SELECT id FROM public.legal_documents
       WHERE doc_type = 'terms_of_use' AND active_to_utc IS NULL LIMIT 1)
   )),
  (SELECT c.id FROM public.user_legal_consents c
    WHERE c.user_id = '00000000-0000-0000-0000-00000000a001'
      AND c.action = 'accepted'
    ORDER BY c.consented_at_utc DESC LIMIT 1),
  'HP8: double accept is idempotent (same consent id)');

SELECT lives_ok(
  $$ SELECT public.withdraw_legal_consent() $$,
  'HP9: withdraw_legal_consent succeeds');

SELECT ok(
  NOT public.has_current_legal_consent('00000000-0000-0000-0000-00000000a001'),
  'HP10: has_current false after withdraw (Art. 8 §5)');

SELECT lives_ok(
  $$ SELECT public.accept_legal_terms(
       (SELECT id FROM public.legal_documents
         WHERE doc_type = 'terms_of_use' AND active_to_utc IS NULL LIMIT 1)
     ) $$,
  'HP11: re-accept after withdraw succeeds');

SELECT ok(
  public.has_current_legal_consent('00000000-0000-0000-0000-00000000a001'),
  'HP12: has_current true after re-accept');

-- ── Adverse: anti-oracle / stale / draft / wrong type ────────────────────────
SELECT throws_ok(
  $$ SELECT public.accept_legal_terms('00000000-0000-0000-0000-00000000dead') $$,
  'P0002', NULL, 'ADV1: missing document rejected (INV-26 anti-oracle)');

SELECT throws_ok(
  $$ SELECT public.accept_legal_terms('00000000-0000-0000-0000-00000000d001') $$,
  'P0002', NULL, 'ADV2: draft document_id rejected (same error as missing)');

-- Closed (inactive) published version must be rejected
RESET ROLE;
UPDATE public.legal_documents
   SET active_to_utc = NOW() - INTERVAL '1 second'
 WHERE doc_type = 'terms_of_use' AND version = '1.0' AND active_to_utc IS NULL;

INSERT INTO public.legal_documents (
  id, doc_type, version, title, body_markdown, content_sha256,
  changelog, status, published_at_utc, active_to_utc
) VALUES (
  '00000000-0000-0000-0000-00000000d002',
  'terms_of_use', '1.1', 'Termos v1.1', 'body v1.1',
  repeat('b', 64), 'changelog v1.1', 'published', NOW(), NULL
);

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000a001","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000b001","role":"TENANT_ADMIN"}}';

-- User accepted 1.0; after publish of 1.1 must be pending again
SELECT ok(
  NOT public.has_current_legal_consent('00000000-0000-0000-0000-00000000a001'),
  'ADV3: version bump forces re-consent (stale 1.0 no longer current)');

SELECT is(
  (SELECT public.get_legal_consent_status() ->> 'status'),
  'pending',
  'ADV3b: get_legal_consent_status pending after version bump (F-07)');

SELECT is(
  (SELECT public.get_legal_consent_status() ->> 'prior_version'),
  '1.0',
  'ADV3c: prior_version exposed for changelog UI (F-07)');

SELECT throws_ok(
  $$ SELECT public.accept_legal_terms(
       (SELECT id FROM public.legal_documents WHERE version = '1.0' AND doc_type = 'terms_of_use' LIMIT 1)
     ) $$,
  'P0002', NULL, 'ADV4: accepting closed version 1.0 rejected');

SELECT lives_ok(
  $$ SELECT public.accept_legal_terms('00000000-0000-0000-0000-00000000d002') $$,
  'ADV5: accepting new active 1.1 succeeds');

SELECT ok(
  public.has_current_legal_consent('00000000-0000-0000-0000-00000000a001'),
  'ADV6: has_current true after accepting 1.1');

RESET ROLE;

-- ── Isolation (INV-22) ───────────────────────────────────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-00000000a002","app_metadata":{"org_id":"00000000-0000-0000-0000-00000000b001","role":"OPERATOR"}}';

SELECT is(
  (SELECT count(*)::int FROM public.user_legal_consents
    WHERE user_id = '00000000-0000-0000-0000-00000000a001'),
  0, 'ISO1: user B cannot SELECT user A consent rows');

-- Forgery: user B cannot accept as user A (uid derived server-side)
SELECT lives_ok(
  $$ SELECT public.accept_legal_terms('00000000-0000-0000-0000-00000000d002') $$,
  'ISO2: user B accept records under B uid (no forgery of A)');

SELECT is(
  (SELECT user_id::text FROM public.user_legal_consents
    WHERE user_id = '00000000-0000-0000-0000-00000000a002'
      AND document_id = '00000000-0000-0000-0000-00000000d002'
      AND action = 'accepted'
    ORDER BY consented_at_utc DESC LIMIT 1),
  '00000000-0000-0000-0000-00000000a002',
  'ISO3: accept binds to JWT sub of caller B (no forgery of A)');

RESET ROLE;

-- ── Telegram: version-aware consent + consent-before-binding ─────────────────
SELECT ok(
  NOT public.has_current_telegram_consent(9000002201),
  'TG1: no telegram consent initially');

-- Stale version row must NOT satisfy current consent
INSERT INTO public.telegram_user_consents (
  chat_id, consent_version, action, accepted_via
) VALUES (9000002201, 'v1_stale', 'accepted', 'telegram_callback');

SELECT ok(
  NOT public.has_current_telegram_consent(9000002201),
  'TG2: stale consent_version does not satisfy current telegram_bot_terms');

SELECT lives_ok(
  $$ SELECT public.accept_telegram_bot_terms(9000002201) $$,
  'TG3: accept_telegram_bot_terms succeeds for current version');

SELECT ok(
  public.has_current_telegram_consent(9000002201),
  'TG4: has_current_telegram_consent true after accept');

-- Binding without consent rejected (different chat)
SELECT throws_ok(
  $$ SELECT * FROM public.consume_telegram_binding_token('ABCD2345', 9000002202) $$,
  '23514', NULL, 'TG5: binding without consent rejected (check_violation)');

-- Happy binding path: consent + valid unused token
INSERT INTO public.telegram_binding_tokens (
  id, organization_id, driver_id, created_by_user_id, code,
  expires_at_utc, created_at_utc
) VALUES (
  '00000000-0000-0000-0000-00000000f001',
  '00000000-0000-0000-0000-00000000b001',
  '00000000-0000-0000-0000-00000000d101',
  '00000000-0000-0000-0000-00000000a001',
  'ABCD2345',
  NOW() + INTERVAL '10 minutes',
  NOW()
);

SELECT lives_ok(
  $$ SELECT * FROM public.consume_telegram_binding_token('ABCD2345', 9000002201) $$,
  'TG6: binding succeeds after current consent');

SELECT is(
  (SELECT count(*)::int FROM public.telegram_chat_bindings
    WHERE chat_id = 9000002201 AND unbound_at_utc IS NULL),
  1, 'TG7: active binding row created for consented chat');

-- Withdraw blocks further current consent
SELECT lives_ok(
  $$ SELECT public.withdraw_telegram_bot_consent(9000002201) $$,
  'TG8: withdraw_telegram_bot_consent succeeds');

SELECT ok(
  NOT public.has_current_telegram_consent(9000002201),
  'TG9: has_current false after telegram withdraw');

SELECT is(
  (SELECT count(*)::int FROM public.telegram_chat_bindings
    WHERE chat_id = 9000002201 AND unbound_at_utc IS NULL),
  0, 'TG10: withdraw unbinds chat (personal-data link severed)');

SELECT * FROM finish();
ROLLBACK;
