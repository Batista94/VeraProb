-- =============================================================================
-- Phase 9.2 — Hotfix: Unique CNPJ (INV-6/INV-1)
-- =============================================================================
-- Organizations may share a name (e.g., franchises), but CNPJ must be strictly
-- unique across the entire platform to guarantee financial isolation.
-- =============================================================================

ALTER TABLE public.organizations
  ADD CONSTRAINT uq_organizations_cnpj UNIQUE (cnpj);
