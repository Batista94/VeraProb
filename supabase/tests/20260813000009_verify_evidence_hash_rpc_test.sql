BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ── Seeds (as postgres: bypasses RLS/grants for fixture setup) ───────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000ea901', 'Org VER', 'Org VER SA', '00000000000a91',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'ver@test.com', 'EXT_VER', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- One disputed queue; the verify RPC reads set_id from here for the mismatch fact.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000ea9e1', '00000000-0000-0000-0000-0000000ea901',
   '00000000-0000-0000-0000-0000000ea9f1', 'set-verify',
   '00000000-0000-0000-0000-0000000ea9aa', '{}'::jsonb, 'disputed');

-- Three PENDING attachments: one that will VERIFY, one that will MISMATCH, one
-- exercising the case-insensitive (lower()) compare. Sealed hashes are lowercase
-- hex per chk_evidence_hash_format.
INSERT INTO public.dispute_evidence_attachments
  (id, organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, uploaded_by, attached_at)
VALUES
  ('00000000-0000-0000-0000-0000000ea9a1', '00000000-0000-0000-0000-0000000ea901',
   '00000000-0000-0000-0000-0000000ea9e1',
   '00000000-0000-0000-0000-0000000ea901/00000000-0000-0000-0000-0000000ea9e1/ok.jpg',
   'ok.jpg', 'image/jpeg', 2048, repeat('a', 64),
   '00000000-0000-0000-0000-0000000ea9b1', '2026-08-13T12:00:00Z'),
  ('00000000-0000-0000-0000-0000000ea9a2', '00000000-0000-0000-0000-0000000ea901',
   '00000000-0000-0000-0000-0000000ea9e1',
   '00000000-0000-0000-0000-0000000ea901/00000000-0000-0000-0000-0000000ea9e1/bad.jpg',
   'bad.jpg', 'image/jpeg', 2048, repeat('b', 64),
   '00000000-0000-0000-0000-0000000ea9b1', '2026-08-13T12:00:00Z'),
  ('00000000-0000-0000-0000-0000000ea9a3', '00000000-0000-0000-0000-0000000ea901',
   '00000000-0000-0000-0000-0000000ea9e1',
   '00000000-0000-0000-0000-0000000ea901/00000000-0000-0000-0000-0000000ea9e1/case.jpg',
   'case.jpg', 'image/jpeg', 2048, repeat('cd', 32),
   '00000000-0000-0000-0000-0000000ea9b1', '2026-08-13T12:00:00Z');

-- ── Structure / grants ───────────────────────────────────────────────────────
-- 1. Signature.
SELECT has_function(
  'public', 'verify_evidence_hash',
  ARRAY['uuid', 'uuid', 'text', 'timestamp with time zone'],
  'verify_evidence_hash exists with the expected signature');

-- 2. SECURITY DEFINER.
SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'verify_evidence_hash'),
  true, 'verify_evidence_hash is SECURITY DEFINER');

-- 3. service_role may execute (trusted edge-function path).
SELECT ok(
  has_function_privilege('service_role',
    'public.verify_evidence_hash(uuid, uuid, text, timestamp with time zone)',
    'EXECUTE'),
  'service_role may execute verify_evidence_hash');

-- 4. authenticated may NOT execute (clients never re-verify their own evidence).
SELECT ok(
  NOT has_function_privilege('authenticated',
    'public.verify_evidence_hash(uuid, uuid, text, timestamp with time zone)',
    'EXECUTE'),
  'authenticated may NOT execute verify_evidence_hash');

-- 5. anon may NOT execute.
SELECT ok(
  NOT has_function_privilege('anon',
    'public.verify_evidence_hash(uuid, uuid, text, timestamp with time zone)',
    'EXECUTE'),
  'anon may NOT execute verify_evidence_hash');

-- ── Trusted edge-function session ────────────────────────────────────────────
SET LOCAL ROLE service_role;

-- 6. VERIFIED: declared hash == recomputed bytes → returns 'VERIFIED'.
SELECT is(
  (SELECT public.verify_evidence_hash(
     '00000000-0000-0000-0000-0000000ea9a1',
     '00000000-0000-0000-0000-0000000ea901',
     repeat('a', 64), '2026-08-13T12:10:00Z')),
  'VERIFIED', 'matching hash returns VERIFIED');

-- 7. Attachment status flipped to VERIFIED.
SELECT is(
  (SELECT verification_status FROM public.dispute_evidence_attachments
    WHERE id = '00000000-0000-0000-0000-0000000ea9a1'),
  'VERIFIED', 'verify flips verification_status to VERIFIED');

-- 8. No EVIDENCE_HASH_MISMATCH fact emitted for a clean verification.
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000ea901'
      AND type = 'EVIDENCE_HASH_MISMATCH'
      AND payload->>'attachment_id' = '00000000-0000-0000-0000-0000000ea9a1'),
  0, 'a clean verification emits no EVIDENCE_HASH_MISMATCH fact');

-- 9. MISMATCH: declared hash != recomputed bytes → returns 'MISMATCH' (D5d, B2).
SELECT is(
  (SELECT public.verify_evidence_hash(
     '00000000-0000-0000-0000-0000000ea9a2',
     '00000000-0000-0000-0000-0000000ea901',
     repeat('e', 64), '2026-08-13T12:11:00Z')),
  'MISMATCH', 'divergent hash returns MISMATCH');

-- 10. Attachment status flipped to MISMATCH (resolve_dispute will hard-block it).
SELECT is(
  (SELECT verification_status FROM public.dispute_evidence_attachments
    WHERE id = '00000000-0000-0000-0000-0000000ea9a2'),
  'MISMATCH', 'verify flips verification_status to MISMATCH');

-- 11. Exactly one EVIDENCE_HASH_MISMATCH fact for the tampered attachment (INV-3).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000ea901'
      AND type = 'EVIDENCE_HASH_MISMATCH'
      AND payload->>'attachment_id' = '00000000-0000-0000-0000-0000000ea9a2'),
  1, 'a mismatch appends exactly one EVIDENCE_HASH_MISMATCH fact (INV-9)');

-- 12. The fact seals both the declared (stored) and recomputed hashes.
SELECT is(
  (SELECT payload->>'declared_hash' || '|' || (payload->>'computed_hash')
     FROM public.sla_audit_ledger_v2
    WHERE type = 'EVIDENCE_HASH_MISMATCH'
      AND payload->>'attachment_id' = '00000000-0000-0000-0000-0000000ea9a2'),
  repeat('b', 64) || '|' || repeat('e', 64),
  'mismatch fact records declared (stored) and computed (recomputed) hashes');

-- 13. set_id is carried from the queue entry into the integrity fact.
SELECT is(
  (SELECT set_id FROM public.sla_audit_ledger_v2
    WHERE type = 'EVIDENCE_HASH_MISMATCH'
      AND payload->>'attachment_id' = '00000000-0000-0000-0000-0000000ea9a2'),
  'set-verify', 'mismatch fact inherits set_id from the queue entry (not the attachment)');

-- 14. Case-insensitive compare: stored lowercase hex, recomputed reported uppercase.
SELECT is(
  (SELECT public.verify_evidence_hash(
     '00000000-0000-0000-0000-0000000ea9a3',
     '00000000-0000-0000-0000-0000000ea901',
     upper(repeat('cd', 32)), '2026-08-13T12:12:00Z')),
  'VERIFIED', 'compare is case-insensitive (lower() normalisation) → VERIFIED');

-- 15. Wrong-org call is rejected with 42501 (anti-oracle, INV-26).
SELECT throws_ok(
  $$ SELECT public.verify_evidence_hash(
       '00000000-0000-0000-0000-0000000ea9a1',
       '00000000-0000-0000-0000-0000000ea9b2',
       'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
       '2026-08-13T12:13:00Z') $$,
  '42501', NULL,
  'wrong-org verify is rejected with 42501 (indistinguishable from not-found)');

-- 16. Unknown attachment id is rejected with 42501 (same opaque error, INV-26).
SELECT throws_ok(
  $$ SELECT public.verify_evidence_hash(
       '00000000-0000-0000-0000-0000000ea9af',
       '00000000-0000-0000-0000-0000000ea901',
       'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
       '2026-08-13T12:14:00Z') $$,
  '42501', NULL,
  'unknown attachment id is rejected with 42501 (anti-oracle parity)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
