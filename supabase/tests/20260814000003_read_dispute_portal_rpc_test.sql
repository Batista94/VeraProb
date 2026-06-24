BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- =============================================================================
-- pgTAP: read_dispute_portal — anon-callable dispute snapshot RPC (5.3)
-- Migration: 20260814000003_read_dispute_portal_rpc.sql
-- Focus: whitelist projection (no fine_cents / storage_path), self-referential
-- snapshot hash, access tracking, ACCESSED ledger fact, anti-oracle on revoke.
-- =============================================================================

-- ── Seeds (as postgres: bypasses RLS/grants) ─────────────────────────────────
INSERT INTO public.organizations (id, name, cnpj, created_at)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001', 'Org Read Portal', '00000000rd0001', NOW())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status,
   disputed_at, disputed_by, resolution_due_at)
VALUES
  ('bbbbbbbb-0000-0000-0000-0000000000e1', 'bbbbbbbb-0000-0000-0000-000000000001',
   'bbbbbbbb-0000-0000-0000-0000000000f1', 'set-read',
   'bbbbbbbb-0000-0000-0000-0000000000aa',
   '{"rule_type":"MAX_TOLERANCE_DELAY","description":"Atraso comprovado","fine_cents":50000}'::jsonb,
   'disputed', NOW(), 'bbbbbbbb-0000-0000-0000-0000000000b1', NOW() + INTERVAL '5 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.dispute_evidence_attachments
  (id, organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, verification_status, uploaded_by, attached_at)
VALUES
  ('bbbbbbbb-0000-0000-0000-0000000000a1', 'bbbbbbbb-0000-0000-0000-000000000001',
   'bbbbbbbb-0000-0000-0000-0000000000e1',
   'bbbbbbbb-0000-0000-0000-000000000001/bbbbbbbb-0000-0000-0000-0000000000e1/laudo.jpg',
   'laudo.jpg', 'image/jpeg', 4096,
   'b1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
   'VERIFIED', 'bbbbbbbb-0000-0000-0000-0000000000b1', '2026-08-13T12:00:00Z')
ON CONFLICT DO NOTHING;

-- Seed a portal token directly (token column defaults to gen_random_uuid()).
INSERT INTO public.dispute_portal_tokens
  (organization_id, queue_entry_id, created_by_user_id, expires_at_utc, max_access_count)
VALUES
  ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-0000000000e1',
   'bbbbbbbb-0000-0000-0000-0000000000b1', NOW() + INTERVAL '24 hours', 5);

CREATE TEMP TABLE _rd_token AS
  SELECT token, id FROM public.dispute_portal_tokens
   WHERE queue_entry_id = 'bbbbbbbb-0000-0000-0000-0000000000e1' LIMIT 1;

-- T1: valid token returns non-null snapshot.
SELECT ok(
  (SELECT read_dispute_portal(token) IS NOT NULL FROM _rd_token),
  'T1: read_dispute_portal returns non-null JSONB for valid token');

-- T2: response NEVER leaks fine_cents (whitelist projection, BIZ amendment).
SELECT ok(
  NOT ((SELECT read_dispute_portal(token)::text FROM _rd_token) LIKE '%fine_cents%'),
  'T2: portal response excludes fine_cents');

-- T3: response NEVER leaks storage_path (information disclosure, QA-Sec T5).
SELECT ok(
  NOT ((SELECT read_dispute_portal(token)::text FROM _rd_token) LIKE '%storage_path%'),
  'T3: portal response excludes storage_path');

-- T4: response carries a self-referential snapshot_hash (INV-9 tamper-evidence).
SELECT ok(
  (SELECT read_dispute_portal(token)::text FROM _rd_token) LIKE '%snapshot_hash%',
  'T4: portal response includes snapshot_hash');

-- T5: access_count increments monotonically (4 reads above -> count = 4).
SELECT is(
  (SELECT access_count FROM public.dispute_portal_tokens
    WHERE queue_entry_id = 'bbbbbbbb-0000-0000-0000-0000000000e1' LIMIT 1),
  4, 'T5: access_count tracks every read');

-- T6: ACCESSED ledger fact logged exactly once (first access only).
SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = 'bbbbbbbb-0000-0000-0000-000000000001'
      AND type = 'DISPUTE_PORTAL_TOKEN_ACCESSED'
      AND payload->>'queue_entry_id' = 'bbbbbbbb-0000-0000-0000-0000000000e1'),
  1, 'T6: DISPUTE_PORTAL_TOKEN_ACCESSED logged once (first access)');

-- T7: revoked token -> identical 42501 (anti-oracle, INV-26).
UPDATE public.dispute_portal_tokens
   SET revoked_at_utc = NOW()
 WHERE queue_entry_id = 'bbbbbbbb-0000-0000-0000-0000000000e1';
SELECT throws_ok(
  $$ SELECT read_dispute_portal(token) FROM _rd_token $$,
  '42501', NULL,
  'T7: read_dispute_portal with revoked token rejected with 42501');

SELECT * FROM finish();
ROLLBACK;
