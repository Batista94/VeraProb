-- Phase 1 — Engine-Version Auditability for contractual_financial_snapshot
-- INV-21: Engine version sealed into snapshot for forensic replay auditability.
-- INV-9:  All timestamps remain UTC (no timestamp changes in this migration).
--
-- Dynamic versioning: engine_version has NO DB default.
-- The application resolves the version from EnvironmentConfig.engineVersion
-- (injected via --dart-define=ENGINE_VERSION=... at build time) and must
-- always supply it on INSERT. This prevents stale version strings from
-- silently propagating into the audit trail.
-- (mirrors policy in 20260601000001_shadow_verdicts.sql)
--
-- Idempotency: ADD COLUMN IF NOT EXISTS + conditional UPDATE guard
-- ensure safe re-execution on any environment.

-- Step 1: Add column as nullable to allow the backfill below.
ALTER TABLE public.contractual_financial_snapshot
  ADD COLUMN IF NOT EXISTS engine_version TEXT;

-- Step 2: Backfill existing rows that predate versioning.
-- Uses a WHERE guard so re-running this migration is a no-op.
UPDATE public.contractual_financial_snapshot
  SET engine_version = 'legacy-unversioned'
  WHERE engine_version IS NULL;

-- Step 3a: Add CHECK constraint with NOT VALID — skips full table scan (non-blocking).
ALTER TABLE public.contractual_financial_snapshot
  ADD CONSTRAINT chk_engine_version_not_null
  CHECK (engine_version IS NOT NULL)
  NOT VALID;

-- Step 3b: Validate constraint — acquires ShareUpdateExclusiveLock only (non-blocking).
ALTER TABLE public.contractual_financial_snapshot
  VALIDATE CONSTRAINT chk_engine_version_not_null;

-- Step 3c: Promote to catalog NOT NULL — metadata-only in PG 12+ after constraint validation.
ALTER TABLE public.contractual_financial_snapshot
  ALTER COLUMN engine_version SET NOT NULL; -- INV-DB: zero-downtime-verified

-- Step 3d: Drop redundant CHECK now that NOT NULL is in the catalog.
ALTER TABLE public.contractual_financial_snapshot
  DROP CONSTRAINT chk_engine_version_not_null;

-- Step 4: Document the forensic intent for future auditors.
COMMENT ON COLUMN public.contractual_financial_snapshot.engine_version IS
  'Engine version that produced this snapshot; app-supplied (no DB default), '
  'sealed for forensic replay. Value ''legacy-unversioned'' indicates rows '
  'created before INV-21 engine-version auditability was introduced.';
