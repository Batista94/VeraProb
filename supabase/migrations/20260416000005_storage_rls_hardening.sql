-- Phase CX-05: Storage RLS Hardening for justification_evidence bucket (INV-2, INV-22)
-- Forensic Audit Signature: CX-05-v2.2
-- Security Guard: INV-24 Compliance Verified
-- Idempotent: safe to re-run on any environment.

-- 1. Ensure bucket exists (idempotent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'justification_evidence',
  'justification_evidence',
  false,
  52428800, -- 50 MB hard cap per file
  ARRAY['image/jpeg','image/png','application/pdf','image/heic','image/heif','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- 2. RLS must be enabled on storage.objects (Supabase enables it by default;
--    this explicit call is a safety net for self-hosted deployments).
DO $$
BEGIN
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Skipping RLS enablement on storage.objects: %', SQLERRM;
END $$;

-- 3. Drop existing policies for this bucket before re-creating (idempotency)
DROP POLICY IF EXISTS "justification_evidence_select" ON storage.objects;
DROP POLICY IF EXISTS "justification_evidence_insert" ON storage.objects;
DROP POLICY IF EXISTS "justification_evidence_delete" ON storage.objects;

-- 4. SELECT: tenant can only read files inside its own org folder (INV-22)
CREATE POLICY "justification_evidence_select"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'justification_evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'organization_id')
  );

-- 5. INSERT: tenant can only write to its own org folder (INV-22)
CREATE POLICY "justification_evidence_insert"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'justification_evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'organization_id')
  );

-- 6. DELETE: tenant can only delete its own org folder files (INV-22)
CREATE POLICY "justification_evidence_delete"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'justification_evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() ->> 'organization_id')
  );
