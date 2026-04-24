-- =============================================================================
-- Migration: Telegram Audio Evidence Support
--
-- Adds mime_type column to telegram_evidence_uploads for autodescriptive
-- media type tracking. Updates storage bucket to accept audio/ogg.
--
-- INV-7:  Append-only — trigger temporarily disabled for backfill only.
-- INV-9:  SHA-256 forensic hash applies to audio files identically.
-- INV-18: mime_type is server-authoritative (magic-byte sniffed), not Telegram metadata.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Add mime_type column (nullable initially for backfill) ────────────────

ALTER TABLE public.telegram_evidence_uploads
  ADD COLUMN IF NOT EXISTS mime_type TEXT;

-- ── 2. Backfill existing rows — requires temporary trigger disable (INV-7) ──

-- Disable immutability trigger for one-shot backfill
ALTER TABLE public.telegram_evidence_uploads DISABLE TRIGGER trg_teu_no_update;

UPDATE public.telegram_evidence_uploads
SET mime_type = CASE
  WHEN file_name ILIKE '%.jpg'  THEN 'image/jpeg'
  WHEN file_name ILIKE '%.jpeg' THEN 'image/jpeg'
  WHEN file_name ILIKE '%.png'  THEN 'image/png'
  WHEN file_name ILIKE '%.webp' THEN 'image/webp'
  WHEN file_name ILIKE '%.heic' THEN 'image/heic'
  WHEN file_name ILIKE '%.heif' THEN 'image/heif'
  WHEN file_name ILIKE '%.mp4'  THEN 'video/mp4'
  WHEN file_name ILIKE '%.pdf'  THEN 'application/pdf'
  WHEN file_name ILIKE '%.ogg'  THEN 'audio/ogg'
  ELSE 'application/octet-stream'
END
WHERE mime_type IS NULL;

-- Re-enable immutability trigger immediately
ALTER TABLE public.telegram_evidence_uploads ENABLE TRIGGER trg_teu_no_update;

-- ── 3. Enforce NOT NULL for new rows via constraint trigger ───────────────
--
-- Non-blocking: avoids the exclusive lock that a column-level NOT NULL constraint requires.
-- Existing rows are already backfilled above; this trigger guards future INSERTs.

CREATE OR REPLACE FUNCTION public.trg_teu_mime_type_not_null()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.mime_type IS NULL THEN
    RAISE EXCEPTION 'mime_type cannot be null'
      USING ERRCODE = '23502'; -- not_null_violation
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_teu_enforce_mime_type ON public.telegram_evidence_uploads;
CREATE TRIGGER trg_teu_enforce_mime_type
  BEFORE INSERT ON public.telegram_evidence_uploads
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_teu_mime_type_not_null();

-- ── 4. Index for media type queries (BI, volumetry reports) ──────────────────

CREATE INDEX IF NOT EXISTS idx_teu_mime_type
  ON public.telegram_evidence_uploads (organization_id, mime_type, telegram_message_date DESC);

-- ── 5. Update storage bucket — add audio/ogg to allowed MIME types ───────────

UPDATE storage.buckets
SET allowed_mime_types = array_append(allowed_mime_types, 'audio/ogg')
WHERE id = 'telegram_evidence'
  AND NOT ('audio/ogg' = ANY(allowed_mime_types));
