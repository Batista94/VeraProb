-- ============================================================
-- veraprob — Optimistic Locking Foundation
-- ============================================================
-- REASON:
--   Prevent "Lost Update" anomalies in multi-user concurrent
--   writes. Every mutable aggregate root (Contract, Vehicle)
--   now carries a `version` column that auto-increments on each
--   UPDATE at the database level.
--
-- STRATEGY:
--   1. Add `version INT NOT NULL DEFAULT 1` column to mutable tables
--   2. Create a shared trigger function `_bump_version_trigger_fn()`
--      that increments version by 1 on every UPDATE
--   3. Attach triggers to each versioned table
--   4. Guard: NEW.version must be > OLD.version (prevents regression)
--
-- SCOPE:
--   - contracts: mutable aggregate root ✓
--   - vehicles: mutable aggregate root ✓
--   - sla_audit_ledger_v2: APPEND-ONLY (INV-3) — NO version column
-- ============================================================

-- ── 1. Add version column ──────────────────────────────────
--
-- DECISION: BIGINT (INT8) instead of INT4.
-- Rationale:
--   - INT4 max (2.1B) would take 68+ years even at 1 update/second.
--   - However, BIGINT ensures consistency with Money.cents (already BIGINT)
--     and eliminates any future risk if versioning is extended to
--     high-throughput tables (telemetry, events).
--   - Storage cost: +4 bytes/row ≈ 40MB for 10M rows — negligible.
--   - Migration cost from INT4→BIGINT later is high — do it right now.

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 1;

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 1;

-- Index for version-aware updates (optimistic lock filter)
CREATE INDEX IF NOT EXISTS idx_contracts_id_version
  ON public.contracts (id, version);

CREATE INDEX IF NOT EXISTS idx_vehicles_id_version
  ON public.vehicles (id, version);

-- ── 2. Shared trigger function ─────────────────────────────

-- This function increments the version column by 1 on every UPDATE.
-- It also enforces that version never goes backwards (INV-10: Fail-Fast).
--
-- SECURITY: Even if an attacker bypasses the application layer and
-- sends a raw UPDATE with a lower version, this trigger REJECTS it.
-- This is Defense in Depth — the database is the last line of defense.
CREATE OR REPLACE FUNCTION public._bump_version_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
  -- Always increment version by 1 on every UPDATE.
  -- This is the authoritative source of version numbering.
  -- Any value sent by the client for the version column is ignored.
  NEW.version := OLD.version + 1;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── 3. Attach triggers to versioned tables ─────────────────

DROP TRIGGER IF EXISTS bump_contracts_version ON public.contracts;
CREATE TRIGGER bump_contracts_version
  BEFORE UPDATE ON public.contracts
  FOR EACH ROW
  EXECUTE FUNCTION public._bump_version_trigger_fn();

DROP TRIGGER IF EXISTS bump_vehicles_version ON public.vehicles;
CREATE TRIGGER bump_vehicles_version
  BEFORE UPDATE ON public.vehicles
  FOR EACH ROW
  EXECUTE FUNCTION public._bump_version_trigger_fn();

-- ── 4. Comments ────────────────────────────────────────────

COMMENT ON COLUMN public.contracts.version IS
  'Optimistic locking version counter. Auto-incremented on each UPDATE. Prevents lost-update anomalies in concurrent writes.';

COMMENT ON COLUMN public.vehicles.version IS
  'Optimistic locking version counter. Auto-incremented on each UPDATE. Prevents lost-update anomalies in concurrent writes.';

COMMENT ON FUNCTION public._bump_version_trigger_fn() IS
  'Ensures version column always increments on UPDATE and never regresses. Prevents lost-update anomalies. Acts as the last line of defense against state reversion attacks.';
