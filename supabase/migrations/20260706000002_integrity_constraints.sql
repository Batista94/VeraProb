-- pr_scanner: ignore-regression
-- =============================================================================
-- Tier-S Data Integrity: Invariant Enforcement (FIX-06)
-- =============================================================================
-- Adds CHECK constraints to organizations table to ensure physical and 
-- financial invariants are never violated at the storage layer.
-- =============================================================================

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_dwell_time_positive 
  CHECK (dwell_time_seconds >= 1);

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_tool_cost_non_negative 
  CHECK (tool_cost_cents >= 0);

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_max_vehicles_positive 
  CHECK (max_vehicles IS NULL OR max_vehicles >= 1);

-- INV-26: Consistency - status must be valid
ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_status_valid
  CHECK (status IN ('ACTIVE', 'ARCHIVED', 'DELETED', 'PENDING'));
