-- ============================================================
-- VeraProb — INV-34: Forensic Domain Sealing
-- ============================================================
-- REASON:
--   Introduces a tamper-evident cryptographic chain (private
--   blockchain) on the two core aggregate roots: contracts and
--   plan_declarations. Any silent mutation of a row after commit
--   becomes detectable by re-computing the hash and comparing it
--   to the stored value.
--
-- STRATEGY: DB-First — PostgreSQL is the sole authority.
--   No application/Dart code participates in hash computation.
--
-- MECHANISM:
--   Each INSERT pins previous_hash = 'GENESIS' and computes
--   current_hash = SHA-256(payload). Each UPDATE chains by setting
--   previous_hash = OLD.current_hash and re-computing current_hash.
--   The payload is built with COALESCE per field and '|' separators
--   to prevent NULL-poisoning and field-boundary collisions.
--
-- TRIGGER EXECUTION ORDER (contracts):
--   bump_contracts_version  → fires first (alphabetically 'b' < 's')
--   seal_contracts_forensic → fires second, sees final NEW.version ✓
--
-- INVARIANTS:
--   INV-9  Evidence Sealing  — SHA-256 at every mutation
--   INV-10 Error Visibility  — RAISE EXCEPTION on NULL payload
--   INV-15 Deterministic     — same inputs → byte-identical hash
--   INV-21 Audit Trail       — current_hash is the Snapshot ID
--   INV-34 Domain Sealing    — GENESIS → chained private blockchain
-- ============================================================


-- ── 1. Sealing Columns ─────────────────────────────────────
--
-- NULL is intentional for rows that pre-date this migration.
-- The chain starts at the first mutation after this migration
-- is applied.

ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS previous_hash TEXT,
  ADD COLUMN IF NOT EXISTS current_hash  TEXT;

ALTER TABLE public.plan_declarations
  ADD COLUMN IF NOT EXISTS previous_hash TEXT,
  ADD COLUMN IF NOT EXISTS current_hash  TEXT;


-- ── 2. Sealing Function ────────────────────────────────────
--
-- Shared trigger function dispatched by TG_TABLE_NAME.
-- Called BEFORE INSERT OR UPDATE on both target tables.
--
-- NULL-Poisoning prevention:
--   PostgreSQL string concatenation with NULL produces NULL.
--   Every field is wrapped in COALESCE(field::text, '') so that
--   a NULL in any column cannot silently zero-out the hash.
--
-- Separator '|' between fields prevents boundary collisions:
--   Without it: COALESCE('ab','') || COALESCE('cd','') = 'abcd'
--   which is indistinguishable from ('a','bcd') or ('abc','d').

CREATE OR REPLACE FUNCTION public.seal_forensic_record()
RETURNS TRIGGER AS $$
DECLARE
  v_payload TEXT;
BEGIN

  -- ── 2a. Establish chain link ──────────────────────────────
  IF TG_OP = 'INSERT' THEN
    -- First record in the chain — no predecessor.
    NEW.previous_hash := 'GENESIS';

  ELSIF TG_OP = 'UPDATE' THEN
    -- Chain: the new block's previous pointer is the old block's hash.
    -- If OLD.current_hash is NULL (pre-migration row being updated for
    -- the first time), treat it as 'GENESIS' to bootstrap the chain.
    NEW.previous_hash := COALESCE(OLD.current_hash, 'GENESIS');

  END IF;

  -- ── 2b. Build payload string ──────────────────────────────
  --
  -- Each table has its own canonical payload. The set of fields
  -- must be stable — adding/removing fields breaks all existing
  -- chains. Any future schema change requires a new INV-34 version.

  IF TG_TABLE_NAME = 'contracts' THEN
    -- Fields: id | version | status | organization_id | previous_hash
    -- version is included AFTER bump_contracts_version has fired,
    -- so it reflects the post-increment value for UPDATEs.
    v_payload :=
      COALESCE(NEW.id::text,                '')  || '|' ||
      COALESCE(NEW.version::text,           '')  || '|' ||
      COALESCE(NEW.status,                  '')  || '|' ||
      COALESCE(NEW.organization_id::text,   '')  || '|' ||
      COALESCE(NEW.previous_hash,           '');

  ELSIF TG_TABLE_NAME = 'plan_declarations' THEN
    -- Fields: id | plan_version | organization_id | original_file_hash | previous_hash
    -- Note: plan_declarations has no `status` column.
    -- Note: version column is `plan_version` (INTEGER), not `version`.
    v_payload :=
      COALESCE(NEW.id::text,                '')  || '|' ||
      COALESCE(NEW.plan_version::text,      '')  || '|' ||
      COALESCE(NEW.organization_id::text,   '')  || '|' ||
      COALESCE(NEW.original_file_hash,      '')  || '|' ||
      COALESCE(NEW.previous_hash,           '');

  ELSE
    -- Guard: this function must never be attached to an unknown table.
    -- Fail loudly rather than silently storing a null hash (INV-10).
    RAISE EXCEPTION
      'seal_forensic_record: unsupported table "%". '
      'Add a payload branch before attaching this trigger.',
      TG_TABLE_NAME;
  END IF;

  -- ── 2c. Compute SHA-256 hash ───────────────────────────────
  --
  -- extensions.digest() is the pgcrypto function, schema-qualified
  -- to avoid search_path manipulation attacks.
  -- encode(..., 'hex') produces a 64-character lowercase hex string.
  NEW.current_hash := encode(
    extensions.digest(v_payload, 'sha256'),
    'hex'
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public, extensions;

COMMENT ON FUNCTION public.seal_forensic_record() IS
  'INV-34 — Forensic Domain Sealing trigger. Builds a SHA-256 hash chain '
  '(GENESIS → chained) for every INSERT/UPDATE on contracts and '
  'plan_declarations. Uses COALESCE per field to prevent NULL-poisoning. '
  'Schema-qualified extensions.digest() prevents search_path attacks. '
  'Do NOT remove or bypass — chain integrity depends on this function '
  'firing on every mutation.';


-- ── 3. Attach Triggers ─────────────────────────────────────

-- ── 3a. contracts ──────────────────────────────────────────
--
-- EXECUTION ORDER with existing triggers (alphabetical, BEFORE):
--   1. bump_contracts_version  → increments NEW.version
--   2. seal_contracts_forensic → hashes with final NEW.version  ✓
--
-- This ordering is load-bearing: the hash must commit the post-bump
-- version, not the pre-bump one. The alphabetical ordering
-- ('b' < 's') guarantees this without explicit sequencing.

DROP TRIGGER IF EXISTS seal_contracts_forensic ON public.contracts;
CREATE TRIGGER seal_contracts_forensic
  BEFORE INSERT OR UPDATE ON public.contracts
  FOR EACH ROW
  EXECUTE FUNCTION public.seal_forensic_record();

COMMENT ON TRIGGER seal_contracts_forensic ON public.contracts IS
  'INV-34 — Fires BEFORE INSERT OR UPDATE. Chains SHA-256 hash using '
  'id|version|status|organization_id|previous_hash. Must fire AFTER '
  'bump_contracts_version (guaranteed by alphabetical order: b < s).';


-- ── 3b. plan_declarations ──────────────────────────────────
--
-- plan_declarations is APPEND-ONLY (INV-3): RLS revokes UPDATE/DELETE.
-- The trigger is declared for INSERT OR UPDATE as defense-in-depth —
-- if the append-only policy is ever relaxed, the chain is maintained.

DROP TRIGGER IF EXISTS seal_plan_declarations_forensic ON public.plan_declarations;
CREATE TRIGGER seal_plan_declarations_forensic
  BEFORE INSERT OR UPDATE ON public.plan_declarations
  FOR EACH ROW
  EXECUTE FUNCTION public.seal_forensic_record();

COMMENT ON TRIGGER seal_plan_declarations_forensic ON public.plan_declarations IS
  'INV-34 — Fires BEFORE INSERT OR UPDATE. Chains SHA-256 hash using '
  'id|plan_version|organization_id|original_file_hash|previous_hash. '
  'In practice only INSERT fires (INV-3 append-only). UPDATE branch '
  'retained for defense-in-depth.';


-- ── 4. Column Comments ─────────────────────────────────────

COMMENT ON COLUMN public.contracts.previous_hash IS
  'INV-34 — Hash of the previous state of this row. Set to ''GENESIS'' '
  'on INSERT. Set to OLD.current_hash on UPDATE. Forms the backward '
  'link in the per-row cryptographic chain.';

COMMENT ON COLUMN public.contracts.current_hash IS
  'INV-34 — SHA-256(id|version|status|organization_id|previous_hash) '
  'in hex. Computed by seal_contracts_forensic BEFORE trigger. '
  'Any external mutation of a row invalidates this hash. '
  'NULL only for rows that pre-date this migration and have not been '
  'subsequently updated.';

COMMENT ON COLUMN public.plan_declarations.previous_hash IS
  'INV-34 — Hash of the previous state of this row. Set to ''GENESIS'' '
  'on INSERT (plan_declarations is append-only per INV-3). '
  'Forms the backward link in the per-row cryptographic chain.';

COMMENT ON COLUMN public.plan_declarations.current_hash IS
  'INV-34 — SHA-256(id|plan_version|organization_id|original_file_hash|previous_hash) '
  'in hex. Computed by seal_plan_declarations_forensic BEFORE trigger. '
  'NULL only for rows that pre-date this migration.';
