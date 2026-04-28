-- =============================================================================
-- Phase 10 — Add dwell_time_seconds to organizations
-- =============================================================================
-- Org-level default stop dwell threshold used by the evaluation engine.
-- INV-14: transport-agnostic config — not vehicle-specific.
-- INV-6: INT seconds avoids TIMESTAMPTZ complexity for a duration field.
-- =============================================================================

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS dwell_time_seconds INT NOT NULL DEFAULT 300;

COMMENT ON COLUMN public.organizations.dwell_time_seconds
  IS 'Default stop dwell threshold in seconds (INV-14). Default 300s = 5 min.';
