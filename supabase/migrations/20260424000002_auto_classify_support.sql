-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: Auto-Classify Support (Phase 10 — Smart Suggestion)
--
-- Adds to telegram_evidence_uploads:
--   suggested_category        TEXT        — GPS-derived classification suggestion
--   suggestion_expires_at_utc TIMESTAMPTZ — 30s window; after expiry pg_cron seals
--   suggestion_sealed_at_utc  TIMESTAMPTZ — set when pg_cron commits the suggestion
--
-- pg_cron job: every minute, seals expired suggestions into telegram_evidence_categories.
-- Effective seal latency: 30–90s (cron minimum 60s granularity — acceptable for logistics).
--
-- INV-6:  TIMESTAMPTZ mandatory — no timestamp without time zone. -- pr_scanner: ignore
-- INV-3:  INSERT into telegram_evidence_categories, ON CONFLICT DO NOTHING (idempotent).
-- INV-15: FOR UPDATE SKIP LOCKED — concurrent-safe, byte-identical re-run.
-- INV-18: GPS comes from EXIF only (Telegram API provides no GPS). Zero-Trust.
-- =============================================================================

SET client_min_messages TO 'WARNING';

ALTER TABLE public.telegram_evidence_uploads
  ADD COLUMN IF NOT EXISTS suggested_category        TEXT,
  ADD COLUMN IF NOT EXISTS suggestion_expires_at_utc TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suggestion_sealed_at_utc  TIMESTAMPTZ;

COMMENT ON COLUMN public.telegram_evidence_uploads.suggested_category IS
  'GPS-derived category suggestion from EXIF geofence (origin→carregamento, dest→lacre). INV-18: EXIF only, never Telegram API.';

COMMENT ON COLUMN public.telegram_evidence_uploads.suggestion_expires_at_utc IS
  'Ingest timestamp + 30s. pg_cron seals this suggestion after expiry. INV-6: TIMESTAMPTZ.';

COMMENT ON COLUMN public.telegram_evidence_uploads.suggestion_sealed_at_utc IS
  'Set by pg_cron when suggestion is committed to telegram_evidence_categories. NULL = pending. INV-15.';

-- pg_cron: seal expired suggestions every minute.
-- Idempotent: ON CONFLICT DO NOTHING + sealed_at guard prevent double-commit.
-- Guard: pg_cron is only available on Supabase Cloud, not local dev (INV-23).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') THEN
    PERFORM cron.schedule(
      'seal-category-suggestions',
      '* * * * *',
      $cron$
        WITH candidates AS (
          SELECT id, organization_id, suggested_category
            FROM public.telegram_evidence_uploads
           WHERE suggested_category IS NOT NULL
             AND suggestion_expires_at_utc < NOW()
             AND suggestion_sealed_at_utc IS NULL
             AND id NOT IN (
                   SELECT evidence_upload_id
                     FROM public.telegram_evidence_categories
                    WHERE evidence_upload_id IS NOT NULL
                 )
           FOR UPDATE SKIP LOCKED  -- INV-15: concurrent-safe
        ),
        inserted AS (
          INSERT INTO public.telegram_evidence_categories (organization_id, evidence_upload_id, category, tagged_at_utc)
          SELECT organization_id, id, suggested_category, NOW() FROM candidates
          ON CONFLICT (evidence_upload_id) DO NOTHING  -- INV-3: idempotent
          RETURNING evidence_upload_id
        )
        UPDATE public.telegram_evidence_uploads
           SET suggestion_sealed_at_utc = NOW()
          FROM inserted
         WHERE public.telegram_evidence_uploads.id = inserted.evidence_upload_id;
      $cron$
    );
  END IF;
END;
$$;
