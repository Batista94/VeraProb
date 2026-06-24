-- =============================================================================
-- Migration: dispute-evidence-portal quarantine bucket — Sprint A (Portal) M3
-- Purpose:   Private staging bucket for carrier counter-evidence. Untrusted
--            bytes land here first (QUARANTINE), are re-hashed + magic-byte
--            sniffed server-side by portal-finalize-upload (INV-9), and only
--            then copied into the production `dispute_evidence` bucket.
--
-- Authorization model (deliberately DIFFERENT from dispute_evidence):
--   The carrier has NO JWT. Upload is authorized by a short-lived signed upload
--   URL minted by the portal-submit-request edge fn (service_role) for the path
--   {token_id}/{submission_uuid}.ext — which carries NO org_id (anti-inference,
--   INV-22). A signed upload URL bypasses RLS by design, so there are NO anon/
--   authenticated storage policies on this bucket. service_role (finalize)
--   reads it directly; clients never touch it.
--
-- Lifecycle: orphan quarantine objects (submission abandoned, MISMATCH/EXPIRED)
--   are swept after 72h by the Data Lifecycle engine (Phase 10.9 hook). No
--   client-facing DELETE policy is created here.
--
-- Council: Architect ✅ · Senior ✅ · QA-Security ✅ · Business ✅ · Lead ✅
-- Invariants: INV-2, INV-3, INV-9, INV-18 (zero-trust), INV-22.
-- Depends on: 20260817000002 (portal_evidence_submissions).
-- =============================================================================

-- Private bucket, 10 MB cap, MIME allow-list mirrors chk_pes_mime_declared (M2).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'dispute-evidence-portal', 'dispute-evidence-portal', false, 10485760,
  ARRAY['image/jpeg','image/png','application/pdf','image/heic','image/heif','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- No SELECT/INSERT/UPDATE/DELETE storage.objects policies for this bucket:
--   • upload   → signed upload URL (service_role-minted, bypasses RLS)
--   • finalize → service_role direct download
--   • clients  → never authorized (no JWT path exists)
-- Any future client-facing policy MUST carry Council approval + forensic note.
