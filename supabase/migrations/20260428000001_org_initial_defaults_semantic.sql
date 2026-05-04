-- pr_scanner: ignore-regression
-- =============================================================================
-- Phase 10.3 — Semantic comments: dwell_time_seconds and max_kinematic_speed_kmh
-- are business configuration defaults, not hard contractual limits.
-- =============================================================================
-- Purpose: Clarify the governance intent of these columns.
-- The SuperAdmin sets the initial default at org creation.
-- The Org Admin can override them via the Operational Parameters panel
-- (UpdateOrgOperationalParamsHandler / update_org_params RPC).
-- =============================================================================
-- INV-14: transport-agnostic config — not vehicle-specific.
-- INV-4: This is a pure metadata migration — no structural changes.
-- =============================================================================

COMMENT ON COLUMN public.organizations.dwell_time_seconds
  IS 'Operational default: stop dwell threshold in seconds (INV-14). '
     'Set by SuperAdmin at org creation as the initial default. '
     'Org Admin can override this value via Configurações > Parâmetros Operacionais. '
     'Default 300s = 5 min. Valid range: 60-1800s.';

-- max_kinematic_speed_kmh lives in the capabilities JSONB column.
-- We document the field semantics here instead.
COMMENT ON COLUMN public.organizations.capabilities
  IS 'JSONB with operational capability flags and initial defaults. '
     'Fields: allows_sealing, allows_loading, allows_cargo_check, allows_incident, '
     'allows_doc, smart_classify (all boolean, nullable = true). '
     'max_kinematic_speed_kmh (Double): kinematic speed alert threshold in km/h. '
     'Set by SuperAdmin as initial default; Org Admin can override via '
     'Configurações > Parâmetros Operacionais. '
     'INV-14: transport-agnostic flags, not enum-locked.';
