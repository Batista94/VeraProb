-- =============================================================================
-- Migration: Contracts natural-key unique index (CSV upsert fallback)
-- Timestamp: 20260730000001
--
-- REASON:
--   Bloco 1D idempotent batch upsert keys on (organization_id, external_id).
--   Contract rows imported WITHOUT an external_id (manual ERP exports that
--   predate anchoring) need a deterministic ON CONFLICT fallback target.
--   Unlike vehicles/drivers/contractors/zones, the contracts table had no
--   natural-key unique constraint. A contract is uniquely identified within a
--   tenant by its name + start of validity window.
--
-- DESIGN DECISIONS:
--   1. UNIQUE INDEX (not blocking ALTER ... ADD CONSTRAINT) — mirrors the
--      20260729000001 external_id pattern; non-blocking on Postgres 11+.
--   2. Key (organization_id, name, valid_from_utc) — org-scoped (INV-1/INV-22),
--      no cross-tenant collision possible.
--   3. A plain (non-partial) unique index: every contract has name +
--      valid_from_utc (both NOT NULL), so no NULL exemption is required.
--
-- SECURITY INVARIANTS:
--   INV-1 / INV-22: organization_id leads the unique key.
--   INV-3: append-only respected — no DROP/DELETE.
--
-- DB GOVERNANCE:
--   No blocking ALTER. No DROP or DELETE operations.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- Natural-key fallback for ON CONFLICT when external_id is absent.
CREATE UNIQUE INDEX IF NOT EXISTS uq_contracts_org_name_validfrom
  ON public.contracts (organization_id, name, valid_from_utc);

COMMENT ON INDEX public.uq_contracts_org_name_validfrom IS
  'Natural-key fallback for idempotent CSV upsert when external_id is NULL.';

-- ── Sanity check: verify index was created ───────────────────────────────────
DO $$
BEGIN
  ASSERT (
    SELECT COUNT(*) FROM pg_indexes
    WHERE indexname = 'uq_contracts_org_name_validfrom'
  ) = 1, 'uq_contracts_org_name_validfrom index not created';
END $$;
