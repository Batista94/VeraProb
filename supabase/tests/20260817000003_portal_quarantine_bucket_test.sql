BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

-- =============================================================================
-- pgTAP: dispute-evidence-portal quarantine bucket — Sprint A M3
-- Covers: bucket exists, private, size cap, MIME allow-list, and (critically)
-- that NO anon/authenticated storage.objects policy references this bucket —
-- authorization is signed-URL only (service_role).
-- =============================================================================

-- B1: bucket exists
SELECT ok(
  EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'dispute-evidence-portal'),
  'B1: dispute-evidence-portal bucket exists');

-- B2: bucket is private
SELECT ok(
  (SELECT NOT public FROM storage.buckets WHERE id = 'dispute-evidence-portal'),
  'B2: bucket is private (public = false)');

-- B3: 10 MB size cap
SELECT is(
  (SELECT file_size_limit FROM storage.buckets WHERE id = 'dispute-evidence-portal'),
  10485760::bigint, 'B3: bucket size limit is 10 MB');

-- B4: MIME allow-list excludes executables (whitelist enforced)
SELECT ok(
  (SELECT 'application/pdf' = ANY(allowed_mime_types)
            AND NOT ('application/x-msdownload' = ANY(allowed_mime_types))
     FROM storage.buckets WHERE id = 'dispute-evidence-portal'),
  'B4: MIME allow-list permits pdf, excludes executables');

-- B5: no storage.objects policy mentions this bucket (signed-URL only)
SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND (qual LIKE '%dispute-evidence-portal%'
           OR with_check LIKE '%dispute-evidence-portal%')),
  0, 'B5: zero client storage policies for quarantine bucket (signed-URL only)');

SELECT * FROM finish();
ROLLBACK;
