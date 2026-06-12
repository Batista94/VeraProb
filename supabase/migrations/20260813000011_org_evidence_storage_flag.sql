-- =============================================================================
-- Migration: org_evidence_storage_flag — Evidence Storage Plan Gate (5.2)
-- Purpose:   Per-org flag that gates dispute-evidence upload behind a paid
--            storage plan. The free tier (1 GB) is exhausted by Tier-1 volume
--            in ~1 month; uploads MUST be contracted. When FALSE, the upload
--            panel renders a clear plan gate (no silent failure).
--
-- Invariants: INV-DB (ADD COLUMN with DEFAULT is instant on PG11+; boolean
--             needs no CHECK), INV-1 (column rides the org row, RLS-scoped).
-- Default FALSE = opt-in: a new org cannot silently consume storage quota.
-- Toggled out-of-band (billing/support), never by the tenant UI.
-- =============================================================================

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS evidence_storage_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.organizations.evidence_storage_enabled IS
  'Componente 5.2: whether the org plan includes paid dispute-evidence storage. '
  'FALSE = upload panel shows a plan gate (no silent failure). Opt-in per contract.';

-- No new grants: the column inherits the existing organizations table grants
-- (tenant admins/auditors already SELECT their own org row via RLS).
