BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ── Seeds (as postgres: bypasses RLS/grants for fixture setup) ───────────────
INSERT INTO public.organizations (
  id, name, legal_name, cnpj, timezone, currency_code,
  plan_type, max_vehicles, max_active_contracts, tool_cost_cents,
  dwell_time_seconds, billing_day, contact_email, external_id,
  organization_type, allowed_domains
) VALUES
  ('00000000-0000-0000-0000-0000000ea301', 'Org ATT', 'Org ATT SA', '00000000000a31',
   'America/Sao_Paulo', 'BRL', 'enterprise', 1000, 50, 15000, 300, 15,
   'att@test.com', 'EXT_ATT', 'LOGISTICS', ARRAY['test.com'])
ON CONFLICT (id) DO NOTHING;

-- Disputed queue (happy path), non-disputed queue (state gate), full queue (limit).
-- contract_id is a UUID-shaped string: the ledger fact casts v_queue.contract_id::uuid.
INSERT INTO public.sanction_review_queue
  (id, organization_id, ledger_entry_id, set_id, contract_id, verdict_evidence, status)
VALUES
  ('00000000-0000-0000-0000-0000000ea3e1', '00000000-0000-0000-0000-0000000ea301',
   '00000000-0000-0000-0000-0000000ea3f1', 'set-att',
   '00000000-0000-0000-0000-0000000ea3aa', '{}'::jsonb, 'disputed'),
  ('00000000-0000-0000-0000-0000000ea3e2', '00000000-0000-0000-0000-0000000ea301',
   '00000000-0000-0000-0000-0000000ea3f2', 'set-att',
   '00000000-0000-0000-0000-0000000ea3aa', '{}'::jsonb, 'pending'),
  ('00000000-0000-0000-0000-0000000ea3e3', '00000000-0000-0000-0000-0000000ea301',
   '00000000-0000-0000-0000-0000000ea3f3', 'set-att',
   '00000000-0000-0000-0000-0000000ea3aa', '{}'::jsonb, 'disputed');

-- Saturate queue e3 with the 10-attachment cap (H2/ADD-3). Distinct hashes
-- (uq_dea_hash_per_queue): two md5 halves = 64 lowercase hex.
INSERT INTO public.dispute_evidence_attachments
  (organization_id, queue_entry_id, storage_path, file_name, mime_type,
   file_size_bytes, sha256_hash, uploaded_by, attached_at)
SELECT
  '00000000-0000-0000-0000-0000000ea301',
  '00000000-0000-0000-0000-0000000ea3e3',
  '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e3/f' || g || '.jpg',
  'f' || g || '.jpg', 'image/jpeg', 1024,
  md5(g::text) || md5((g + 100)::text),
  '00000000-0000-0000-0000-0000000ea3b1', NOW()
FROM generate_series(1, 10) AS g;

-- ── Structure / grants ───────────────────────────────────────────────────────
SELECT has_function(
  'public', 'attach_dispute_evidence',
  ARRAY['uuid', 'uuid', 'text', 'text', 'text', 'bigint', 'text', 'uuid',
        'timestamp with time zone'],
  'attach_dispute_evidence exists with the expected signature');

SELECT is(
  (SELECT prosecdef FROM pg_proc WHERE proname = 'attach_dispute_evidence'),
  true, 'attach_dispute_evidence is SECURITY DEFINER');

SELECT ok(
  has_function_privilege('authenticated',
    'public.attach_dispute_evidence(uuid, uuid, text, text, text, bigint, text, uuid, timestamp with time zone)',
    'EXECUTE'),
  'authenticated may execute attach_dispute_evidence');

SELECT ok(
  NOT has_function_privilege('anon',
    'public.attach_dispute_evidence(uuid, uuid, text, text, text, bigint, text, uuid, timestamp with time zone)',
    'EXECUTE'),
  'anon may NOT execute attach_dispute_evidence');

SELECT ok(
  NOT has_function_privilege('service_role',
    'public.attach_dispute_evidence(uuid, uuid, text, text, text, bigint, text, uuid, timestamp with time zone)',
    'EXECUTE'),
  'service_role may NOT execute attach_dispute_evidence (no Data-API bypass)');

-- ── Happy path: authenticated TENANT_ADMIN of Org ATT ────────────────────────
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000ea3b1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ea301","role":"TENANT_ADMIN"}}';

SELECT lives_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e1',
       '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e1/photo.jpg',
       'photo.jpg', 'image/jpeg', 2048,
       'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3b1', '2026-08-13T12:00:00Z'
     ) $$,
  'attach_dispute_evidence inserts metadata for an owning TENANT_ADMIN');

SELECT is(
  (SELECT verification_status FROM public.dispute_evidence_attachments
    WHERE queue_entry_id = '00000000-0000-0000-0000-0000000ea3e1'),
  'PENDING', 'new attachment lands with verification_status PENDING (B2 re-verify pending)');

SELECT is(
  (SELECT count(*)::int FROM public.sla_audit_ledger_v2
    WHERE organization_id = '00000000-0000-0000-0000-0000000ea301'
      AND type = 'DISPUTE_EVIDENCE_ATTACHED'
      AND payload->>'queue_entry_id' = '00000000-0000-0000-0000-0000000ea3e1'),
  1, 'each upload appends exactly one DISPUTE_EVIDENCE_ATTACHED fact (ADD-1)');

-- ── Cross-tenant: Org B JWT attaches to Org ATT queue → 42501 (INV-22, B4) ───
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000ea3b1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ea3b2","role":"TENANT_ADMIN"}}';
SELECT throws_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e1',
       '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e1/x.jpg',
       'x.jpg', 'image/jpeg', 1024,
       'b1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3b1', '2026-08-13T12:01:00Z'
     ) $$,
  '42501', NULL,
  'cross-tenant attach is rejected with 42501 (anti-oracle, INV-22/26)');

-- ── Wrong role: OPERATOR of Org ATT → 42501 (server-side RBAC) ───────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000ea3b1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ea301","role":"OPERATOR"}}';
SELECT throws_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e1',
       '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e1/x.jpg',
       'x.jpg', 'image/jpeg', 1024,
       'c1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3b1', '2026-08-13T12:02:00Z'
     ) $$,
  '42501', NULL,
  'OPERATOR role is rejected with 42501');

-- ── Back to a valid TENANT_ADMIN session for the remaining gates ─────────────
SET LOCAL request.jwt.claims =
  '{"role":"authenticated","sub":"00000000-0000-0000-0000-0000000ea3b1","app_metadata":{"org_id":"00000000-0000-0000-0000-0000000ea301","role":"TENANT_ADMIN"}}';

-- uploaded_by spoof: JWT sub <> p_uploaded_by → 42501 (provenance bind).
SELECT throws_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e1',
       '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e1/x.jpg',
       'x.jpg', 'image/jpeg', 1024,
       'd1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3c9', '2026-08-13T12:03:00Z'
     ) $$,
  '42501', NULL,
  'uploaded_by spoof (sub <> p_uploaded_by) is rejected with 42501');

-- Path not bound to {org}/{queue}/ → 42501 (B4 path bind).
SELECT throws_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e1',
       'someone-else/00000000-0000-0000-0000-0000000ea3e1/x.jpg',
       'x.jpg', 'image/jpeg', 1024,
       'e1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3b1', '2026-08-13T12:04:00Z'
     ) $$,
  '42501', NULL,
  'storage path not bound to {org}/{queue}/ is rejected with 42501 (B4)');

-- Queue not in disputed state → 42501 (state gate).
SELECT throws_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e2',
       '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e2/x.jpg',
       'x.jpg', 'image/jpeg', 1024,
       'f1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3b1', '2026-08-13T12:05:00Z'
     ) $$,
  '42501', NULL,
  'attaching to a non-disputed queue is rejected with 42501');

-- 10-attachment cap reached on queue e3 → P0001 (H2/ADD-3, race-free under lock).
SELECT throws_ok(
  $$ SELECT public.attach_dispute_evidence(
       '00000000-0000-0000-0000-0000000ea301',
       '00000000-0000-0000-0000-0000000ea3e3',
       '00000000-0000-0000-0000-0000000ea301/00000000-0000-0000-0000-0000000ea3e3/over.jpg',
       'over.jpg', 'image/jpeg', 1024,
       '0a0b0c0d0e0f0718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
       '00000000-0000-0000-0000-0000000ea3b1', '2026-08-13T12:06:00Z'
     ) $$,
  'P0001', NULL,
  '11th attachment past the 10-cap is rejected with P0001 (H2/ADD-3)');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
