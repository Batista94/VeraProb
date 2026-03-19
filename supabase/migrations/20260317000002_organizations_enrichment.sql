-- ============================================================
-- veraprob — Phase 6: Organizations Enrichment
-- ============================================================
-- REASON:
--   Add columns to support self-service branding, localization,
--   and financial settings per organization.
-- ============================================================

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS timezone       TEXT DEFAULT 'America/Sao_Paulo',
  ADD COLUMN IF NOT EXISTS currency_code   TEXT DEFAULT 'BRL',
  ADD COLUMN IF NOT EXISTS logo_url        TEXT;

-- Seed default values for existing organizations if any
UPDATE public.organizations
SET 
  timezone = 'America/Sao_Paulo'
WHERE timezone IS NULL;

UPDATE public.organizations
SET 
  currency_code = 'BRL'
WHERE currency_code IS NULL;
