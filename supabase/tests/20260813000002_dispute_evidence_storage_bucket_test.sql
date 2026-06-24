BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

-- ── Bucket config (INV-22 isolation, MIME/size parity with mig 001) ──────────
SELECT ok(
  EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'dispute_evidence'),
  'dispute_evidence bucket exists');

SELECT is(
  (SELECT public FROM storage.buckets WHERE id = 'dispute_evidence'),
  false, 'dispute_evidence bucket is private (not public)');

SELECT is(
  (SELECT file_size_limit FROM storage.buckets WHERE id = 'dispute_evidence'),
  10485760::bigint, 'file_size_limit is 10 MB');

SELECT ok(
  (SELECT allowed_mime_types @> ARRAY['image/jpeg','application/pdf']
     FROM storage.buckets WHERE id = 'dispute_evidence'),
  'allowed_mime_types includes image/jpeg and application/pdf');

-- ── Storage RLS policies (INV-2, INV-22) ─────────────────────────────────────
SELECT ok(
  EXISTS (SELECT 1 FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects'
       AND policyname='dispute_evidence_select' AND cmd='SELECT'),
  'dispute_evidence_select SELECT policy exists');

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects'
       AND policyname='dispute_evidence_insert' AND cmd='INSERT'),
  'dispute_evidence_insert INSERT policy exists');

SELECT ok(
  (SELECT qual LIKE '%app_metadata%' AND qual LIKE '%org_id%'
     FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
      AND policyname='dispute_evidence_select'),
  'select policy gates the org_id folder segment (tenant isolation)');

SELECT ok(
  (SELECT with_check LIKE '%array_length%'
     FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
      AND policyname='dispute_evidence_insert'),
  'insert policy requires the queue_entry_id folder segment (B4)');

-- ── No client mutation of sealed blobs (INV-3, INV-9) ────────────────────────
SELECT is(
  (SELECT count(*)::int FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects'
       AND policyname LIKE 'dispute_evidence%' AND cmd='DELETE'),
  0, 'no client DELETE policy (files are cryptographic proofs, LGPD-gated)');

SELECT is(
  (SELECT count(*)::int FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects'
       AND policyname LIKE 'dispute_evidence%' AND cmd='UPDATE'),
  0, 'no client UPDATE policy (blobs immutable once written)');

SELECT * FROM finish();
ROLLBACK;
