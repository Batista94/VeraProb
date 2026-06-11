-- =============================================================================
-- Migration: dispute_evidence storage bucket — tenant-isolated evidence blobs
-- Purpose:   Private bucket for dispute evidence files. Folder-based tenant
--            isolation (INV-22): path = {org_id}/{queue_entry_id}/{file_uuid}.ext.
--            Storage RLS gates the org_id segment; queue ownership is enforced by
--            the attach_dispute_evidence RPC (B4). Client DELETE permanently
--            blocked — files are cryptographic proofs (INV-3, INV-9).
--
-- Invariants: INV-2, INV-3, INV-9, INV-22.
-- =============================================================================

-- Private bucket, 10 MB cap, MIME allow-list mirrors chk_evidence_mime (mig 001).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'dispute_evidence', 'dispute_evidence', false, 10485760,
  ARRAY['image/jpeg','image/png','application/pdf','image/heic','image/heif','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Path convention: dispute_evidence/{org_id}/{queue_entry_id}/{file_uuid}.ext
-- NOTE (B4): storage RLS cannot JOIN application tables, so it gates ONLY the
-- org_id segment. queue_entry_id ownership is enforced by attach_dispute_evidence
-- (the metadata row is the source of truth; an orphan blob with no metadata row
-- is unreachable by the app and swept by the LGPD lifecycle job, Phase 10.9).
DROP POLICY IF EXISTS "dispute_evidence_select" ON storage.objects;
CREATE POLICY "dispute_evidence_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'dispute_evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() -> 'app_metadata' ->> 'org_id')
  );

DROP POLICY IF EXISTS "dispute_evidence_insert" ON storage.objects;
CREATE POLICY "dispute_evidence_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'dispute_evidence'
    AND (storage.foldername(name))[1] = (auth.jwt() -> 'app_metadata' ->> 'org_id')
    AND (storage.foldername(name))[2] IS NOT NULL            -- queue folder present
    AND array_length(storage.foldername(name), 1) >= 2
  );

-- LGPD-retention (Phase 10.9): deletion ONLY via service_role through the
-- lifecycle engine with a mandatory audit trail. Client-facing DELETE is
-- permanently blocked — evidence files are cryptographic proofs. Any future
-- DELETE policy MUST be added with Council approval and forensic justification.
-- (No UPDATE policy either: blobs are immutable once written.)
