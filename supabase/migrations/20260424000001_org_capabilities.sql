-- =============================================================================
-- Migration: Organization Capabilities (Phase 10 — Enterprise Intelligence Layer)
--
-- Adds:
--   organization_type TEXT  — cosmetic label (CARGO/PASSENGER/URBAN_LOGISTICS/etc.)
--   capabilities JSONB      — operational feature flags per tenant
--
-- INV-14: capability flags, NOT enum — transport-agnostic Core, no vertical leak.
-- INV-1:  RLS unchanged — existing SELECT policy on organizations covers capabilities.
-- INV-22: capabilities are per-org — Tenant-A cannot see Tenant-B flags.
--
-- Safe default: all flags true → existing orgs see all categories unchanged.
-- NULL capabilities treated as all-true in application layer (OrgCapabilities.fromJson).
-- =============================================================================

SET client_min_messages TO 'WARNING';

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS organization_type TEXT,
  ADD COLUMN IF NOT EXISTS capabilities JSONB NOT NULL DEFAULT '{
    "allows_sealing":       true,
    "allows_loading":       true,
    "allows_cargo_check":   true,
    "allows_incident":      true,
    "allows_doc":           true,
    "smart_classify":       true
  }'::jsonb;

COMMENT ON COLUMN public.organizations.organization_type IS
  'Cosmetic tenant label (e.g. CARGO, PASSENGER, URBAN_LOGISTICS). No domain logic — use capabilities flags instead. INV-14.';

COMMENT ON COLUMN public.organizations.capabilities IS
  'Operational feature flags JSONB. Keys: allows_sealing, allows_loading, allows_cargo_check, allows_incident, allows_doc, smart_classify. NULL-safe: missing key defaults to true. INV-14.';
