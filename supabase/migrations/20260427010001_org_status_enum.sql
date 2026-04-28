-- =============================================================================
-- Stage A.1 — Organization Status Lifecycle Enum
-- =============================================================================
-- Replaces the boolean `is_active` with a full lifecycle status column.
-- `is_active` becomes a GENERATED ALWAYS column for retro-compatibility with
-- existing RLS policies and application code.
--
-- Lifecycle: TRIAL → ACTIVE → SUSPENDED → CHURNED → DELETED
--
-- INV-1: org_id filter ALL — status is per-org.
-- INV-3: Status changes are audited in system_audit_log (Stage C).
-- =============================================================================

-- ── Step 1: Add status column with CHECK constraint ──────────────────────────
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (status IN ('TRIAL', 'ACTIVE', 'SUSPENDED', 'CHURNED', 'DELETED'));

-- ── Step 2: Backfill from existing is_active boolean ─────────────────────────
-- is_active = TRUE  → ACTIVE
-- is_active = FALSE → SUSPENDED (conservative; admin can reclassify later)
UPDATE public.organizations
  SET status = CASE WHEN is_active = TRUE THEN 'ACTIVE' ELSE 'SUSPENDED' END
  WHERE status = 'ACTIVE' AND is_active = FALSE;

-- ── Step 3: Replace is_active with a generated column ────────────────────────
-- First drop the old column, then recreate as generated.
-- This is safe because all existing code reads is_active, which will now
-- be derived from status.
ALTER TABLE public.organizations
  DROP COLUMN IF EXISTS is_active;

ALTER TABLE public.organizations
  ADD COLUMN is_active BOOLEAN GENERATED ALWAYS AS (status = 'ACTIVE') STORED;

-- ── Step 4: Index for status filtering (SuperAdmin dashboard) ────────────────
CREATE INDEX IF NOT EXISTS idx_organizations_status
  ON public.organizations (status);

-- ── Step 5: Update plan_type CHECK to include status-aware validation ────────
COMMENT ON COLUMN public.organizations.status IS
  'Organization lifecycle: TRIAL → ACTIVE → SUSPENDED → CHURNED → DELETED. '
  'is_active is a generated column derived from this field for retro-compatibility.';

COMMENT ON COLUMN public.organizations.is_active IS
  'GENERATED ALWAYS AS (status = ''ACTIVE''). Retro-compatible with existing RLS and app code.';
