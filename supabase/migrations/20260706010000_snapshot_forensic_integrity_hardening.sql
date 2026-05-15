-- =============================================================================
-- Migration: 20260706010000 — contractual_financial_snapshot forensic hardening
--
-- Closes three forensic-integrity gaps surfaced by the QA audit of the snapshot
-- table (test plan: tests/plans/20260514000000_snapshot_engine_version_test_plan.md,
-- group G6):
--
--   BUG-1 (INV-5 / INV-15): risk_percentage and loss_percentage were stored as
--       FLOAT8 (double precision). Basis points are integers by definition; float
--       storage permits non-deterministic fractional values that the Dart domain
--       layer silently truncates via `.toInt()`, breaking byte-identical replay.
--       The names were also misleading (a "percentage" column holding 500 means
--       5%, not 500%). Fix: introduce INTEGER basis-point columns
--       risk_percentage_bps / loss_percentage_bps — matching the domain fields
--       riskPercentageBps / lossPercentageBps — via the zero-downtime
--       add / backfill / promote pattern (INV-DB). EXPAND-AND-CONTRACT phase 1:
--       the legacy float columns are kept and formally deprecated, not dropped;
--       contraction is deferred to the Phase 3 cleanup migration.
--
--   BUG-2 (forensic ambiguity): last_ledger_entry_id (BIGINT, v1 ledger) and
--       last_ledger_entry_uuid (TEXT, v2 ledger) could both be populated, leaving
--       no deterministic answer to "which ledger entry sealed this snapshot".
--       Fix: a mutually-exclusive CHECK constraint plus disambiguating COMMENTs
--       declaring last_ledger_entry_uuid as the canonical reference.
--
--   BUG-3 (INV-3): the table is declared IMMUTABLE and carries REVOKE
--       UPDATE/DELETE, but REVOKE does not stop service_role. No trigger enforced
--       immutability at the Postgres level — unlike sla_audit_ledger /
--       sla_audit_ledger_v2. The vestigial updated_at column further implied the
--       row was mutable. Fix: BEFORE UPDATE/DELETE guard triggers (mirroring the
--       ledger pattern). updated_at is formally deprecated in place (not
--       dropped) under EXPAND-AND-CONTRACT phase 1; the trigger makes it inert.
--
-- Ordering: BUG-1 runs first because its backfill issues UPDATEs; the BUG-3
-- immutability trigger is created last so it never blocks that backfill.
--
-- Idempotency: BUG-1 is gated on the legacy column still being `double
-- precision` and every step inside is re-run safe (IF NOT EXISTS / WHERE-guarded
-- backfill / constraints dropped before re-add); BUG-2/BUG-3 use IF [NOT] EXISTS
-- guards. Safe to re-run.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ─────────────────────────────────────────────────────────────────────────────
-- BUG-1 — risk_percentage / loss_percentage : FLOAT8 columns replaced by
--          INTEGER basis-point columns risk_percentage_bps / loss_percentage_bps.
-- The whole transformation is gated on the legacy float column still being
-- `double precision`; every step inside is individually re-run safe, so a
-- re-run converges to the same state (EXPAND-AND-CONTRACT phase 1 — the legacy
-- columns are kept and deprecated, not dropped).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'contractual_financial_snapshot'
      AND column_name  = 'risk_percentage'
      AND data_type    = 'double precision'
  ) THEN

    -- Step 1: add the integer bps columns as nullable (instant, metadata-only).
    ALTER TABLE public.contractual_financial_snapshot
      ADD COLUMN IF NOT EXISTS risk_percentage_bps INTEGER,
      ADD COLUMN IF NOT EXISTS loss_percentage_bps INTEGER;

    -- Step 2: backfill from the legacy float columns. round() recovers the
    -- nearest integer basis point for any historical fractional values.
    UPDATE public.contractual_financial_snapshot
      SET risk_percentage_bps = round(risk_percentage)::int,
          loss_percentage_bps = round(loss_percentage)::int
      WHERE risk_percentage_bps IS NULL
         OR loss_percentage_bps IS NULL;

    -- Step 3: promote to NOT NULL via the zero-downtime CHECK pattern (INV-DB).
    -- NOT VALID skips the full-table scan; VALIDATE then runs it under a weaker
    -- ShareUpdateExclusiveLock instead of AccessExclusiveLock.
    ALTER TABLE public.contractual_financial_snapshot
      ADD CONSTRAINT chk_risk_pct_bps_not_null CHECK (risk_percentage_bps IS NOT NULL) NOT VALID,
      ADD CONSTRAINT chk_loss_pct_bps_not_null CHECK (loss_percentage_bps IS NOT NULL) NOT VALID;

    ALTER TABLE public.contractual_financial_snapshot
      VALIDATE CONSTRAINT chk_risk_pct_bps_not_null;
    ALTER TABLE public.contractual_financial_snapshot
      VALIDATE CONSTRAINT chk_loss_pct_bps_not_null;

    ALTER TABLE public.contractual_financial_snapshot
      ALTER COLUMN risk_percentage_bps SET NOT NULL, -- INV-DB: zero-downtime-verified
      ALTER COLUMN loss_percentage_bps SET NOT NULL; -- INV-DB: zero-downtime-verified

    ALTER TABLE public.contractual_financial_snapshot
      DROP CONSTRAINT chk_risk_pct_bps_not_null,
      DROP CONSTRAINT chk_loss_pct_bps_not_null;

    -- Step 4: EXPAND-AND-CONTRACT phase 1 (Expansion only). The legacy float
    -- columns are NOT dropped here — they remain for rollback safety and
    -- forensic parity during the transition. Contraction (DROP COLUMN) is
    -- deferred to the Phase 3 cleanup migration. They are formally deprecated
    -- in place so no application code adopts them.
    COMMENT ON COLUMN public.contractual_financial_snapshot.risk_percentage IS
      'DEPRECATED: Use risk_percentage_bps. Scheduled for removal in Phase 3 cleanup.';
    COMMENT ON COLUMN public.contractual_financial_snapshot.loss_percentage IS
      'DEPRECATED: Use loss_percentage_bps. Scheduled for removal in Phase 3 cleanup.';

    -- Step 5: document the integer basis-point contract for future auditors.
    COMMENT ON COLUMN public.contractual_financial_snapshot.risk_percentage_bps IS
      'Revenue-at-risk ratio in INTEGER basis points (1% = 100 bps). INV-5/INV-15: '
      'integer-only — the predecessor float column risk_percentage permitted '
      'non-deterministic fractional values that the domain layer silently '
      'truncated, breaking byte-identical replay.';
    COMMENT ON COLUMN public.contractual_financial_snapshot.loss_percentage_bps IS
      'Lost-revenue ratio in INTEGER basis points (1% = 100 bps). INV-5/INV-15: '
      'integer-only — see risk_percentage_bps.';

  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- BUG-2 — ledger reference disambiguation
-- last_ledger_entry_id (v1, BIGINT) and last_ledger_entry_uuid (v2, TEXT/UUID)
-- must never both be populated; last_ledger_entry_uuid is canonical.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entry_ref_exclusive'
  ) THEN
    ALTER TABLE public.contractual_financial_snapshot
      ADD CONSTRAINT chk_ledger_entry_ref_exclusive
      CHECK (last_ledger_entry_id IS NULL OR last_ledger_entry_uuid IS NULL)
      NOT VALID;
  END IF;
END $$;

-- VALIDATE is a no-op if the constraint is already valid (safe to re-run).
ALTER TABLE public.contractual_financial_snapshot
  VALIDATE CONSTRAINT chk_ledger_entry_ref_exclusive;

COMMENT ON COLUMN public.contractual_financial_snapshot.last_ledger_entry_id IS
  'LEGACY (v1 ledger). BIGINT id of the sla_audit_ledger entry that sealed this '
  'snapshot. Populated only for snapshots created before the v2 UUID ledger. '
  'Mutually exclusive with last_ledger_entry_uuid (chk_ledger_entry_ref_exclusive). '
  'Application code must not write this column.';

COMMENT ON COLUMN public.contractual_financial_snapshot.last_ledger_entry_uuid IS
  'CANONICAL (v2 ledger). UUID of the sla_audit_ledger_v2 entry that sealed this '
  'snapshot — the authoritative causal boundary for forensic replay (INV-15/INV-21). '
  'Mutually exclusive with the legacy last_ledger_entry_id.';

-- ─────────────────────────────────────────────────────────────────────────────
-- BUG-3 — Postgres-level immutability (INV-3)
-- REVOKE UPDATE/DELETE does not stop service_role; a trigger fires before ALL
-- operations regardless of role. Mirrors prevent_ledger_v2_mutation().
-- updated_at is vestigial: on an append-only table it is always equal to
-- created_at and falsely implies the row can be mutated. EXPAND-AND-CONTRACT
-- phase 1 — it is NOT dropped here (rollback safety / forensic parity); it is
-- formally deprecated in place and the immutability trigger below makes it
-- inert. Contraction (DROP COLUMN) is deferred to the Phase 3 cleanup migration.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'contractual_financial_snapshot'
      AND column_name  = 'updated_at'
  ) THEN
    COMMENT ON COLUMN public.contractual_financial_snapshot.updated_at IS
      'DEPRECATED: Vestigial on an append-only table (always equals created_at). '
      'Scheduled for removal in Phase 3 cleanup.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.prevent_contractual_snapshot_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION
    'contractual_financial_snapshot is immutable (INV-3). Operation: %, id: %',
    TG_OP,
    OLD.id
  USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_no_update ON public.contractual_financial_snapshot;
CREATE TRIGGER trg_snapshot_no_update
  BEFORE UPDATE ON public.contractual_financial_snapshot
  FOR EACH ROW EXECUTE FUNCTION public.prevent_contractual_snapshot_mutation();

DROP TRIGGER IF EXISTS trg_snapshot_no_delete ON public.contractual_financial_snapshot;
CREATE TRIGGER trg_snapshot_no_delete
  BEFORE DELETE ON public.contractual_financial_snapshot
  FOR EACH ROW EXECUTE FUNCTION public.prevent_contractual_snapshot_mutation();
