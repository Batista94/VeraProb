-- =============================================================================
-- Migration: Add external_id ERP Integration Anchor
-- Timestamp: 20260729000001
--
-- REASON:
--   The Universal CSV Importer requires a stable, client-controlled dedup key
--   that survives corrections (e.g., typo in plate fixed in ERP must UPDATE,
--   not INSERT a duplicate). Natural keys (plate, license_number, CNPJ) are
--   mutable; external_id is the immutable ERP integration anchor.
--
-- DESIGN DECISIONS:
--   1. NULLABLE by default — rows created manually via UI have no external_id.
--   2. UNIQUE per (organization_id, external_id) — idempotency constraint for
--      CSV upsert via ON CONFLICT.
--   3. Partial unique index (WHERE external_id IS NOT NULL) — standard Postgres
--      pattern to allow multiple NULLs while enforcing uniqueness on non-null
--      values. NULLs are intentionally exempt (INV-3 append-only manual rows).
--   4. Zero-downtime: uses ADD COLUMN (non-blocking on Postgres 11+).
--      No VALIDATE CONSTRAINT needed because the column is nullable.
--
-- SECURITY INVARIANTS:
--   INV-1: organization_id in every constraint.
--   INV-2: RLS on all tables already enforced by previous migrations.
--   INV-3: Append-only constraint respected — manual rows unaffected.
--   INV-22: No cross-tenant key collision possible (org_id in unique index).
--
-- DB GOVERNANCE:
--   No blocking ALTER. Partial unique index on nullable column is non-blocking.
--   No DROP or DELETE operations.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. vehicles ───────────────────────────────────────────────────────────────

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS external_id TEXT;

-- Partial unique index: NULL values are exempt (manual UI rows)
CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_org_external_id
  ON public.vehicles (organization_id, external_id)
  WHERE external_id IS NOT NULL;

COMMENT ON COLUMN public.vehicles.external_id IS
  'ERP integration anchor for idempotent CSV upsert. NULL for manual UI rows.';

-- ── 2. drivers ────────────────────────────────────────────────────────────────

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS external_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_drivers_org_external_id
  ON public.drivers (organization_id, external_id)
  WHERE external_id IS NOT NULL;

COMMENT ON COLUMN public.drivers.external_id IS
  'ERP integration anchor for idempotent CSV upsert. NULL for manual UI rows.';

-- ── 3. contractors ────────────────────────────────────────────────────────────

ALTER TABLE public.contractors
  ADD COLUMN IF NOT EXISTS external_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_contractors_org_external_id
  ON public.contractors (organization_id, external_id)
  WHERE external_id IS NOT NULL;

COMMENT ON COLUMN public.contractors.external_id IS
  'ERP integration anchor for idempotent CSV upsert. NULL for manual UI rows.';

-- ── 4. contracts ─────────────────────────────────────────────────────────────
-- Note: the contracts table is in public schema per 20260310000000_contract_lifecycle.sql

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS external_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_contracts_org_external_id
  ON public.contracts (organization_id, external_id)
  WHERE external_id IS NOT NULL;

COMMENT ON COLUMN public.contracts.external_id IS
  'ERP integration anchor for idempotent CSV upsert. NULL for manual UI rows.';

-- ── 5. operational_zones ─────────────────────────────────────────────────────

ALTER TABLE public.operational_zones
  ADD COLUMN IF NOT EXISTS external_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_operational_zones_org_external_id
  ON public.operational_zones (organization_id, external_id)
  WHERE external_id IS NOT NULL;

COMMENT ON COLUMN public.operational_zones.external_id IS
  'ERP integration anchor for idempotent CSV upsert. NULL for manual UI rows.';

-- ── 6. Explicit Data API grants (INV-DATA-API-GRANT) ─────────────────────────
-- The new column is inherited by the existing table grants.
-- No additional GRANT needed — column-level grants not required on Postgres RLS.

-- ── Sanity check: verify indexes were created ─────────────────────────────────
DO $$
BEGIN
  ASSERT (
    SELECT COUNT(*) FROM pg_indexes
    WHERE indexname IN (
      'uq_vehicles_org_external_id',
      'uq_drivers_org_external_id',
      'uq_contractors_org_external_id',
      'uq_contracts_org_external_id',
      'uq_operational_zones_org_external_id'
    )
  ) = 5, 'external_id unique indexes not fully created';
END $$;
