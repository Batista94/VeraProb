-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: tool_cost_cents on organizations (Phase 10 — ROI Engine)
--
-- INV-4: BIGINT cents. NULL = not yet configured → ROI shows N/A.
-- =============================================================================

SET client_min_messages TO 'WARNING';

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS tool_cost_cents BIGINT;

COMMENT ON COLUMN public.organizations.tool_cost_cents IS
  'Monthly SaaS cost per tenant in cents (INV-4). NULL = not configured → ROI = N/A.';
