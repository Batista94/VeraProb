-- Migration: CSV Mapping Templates — soft-delete + RLS hardening
-- INV-1:  org_id filter enforced at both Dart and DB layers
-- INV-3:  append-only semantics — hard DELETE replaced by soft-delete
-- INV-DB: non-destructive ADD COLUMN IF NOT EXISTS (zero-downtime)

-- ── Step 1: Soft-delete column ────────────────────────────────────────────

ALTER TABLE public.csv_mapping_templates
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.csv_mapping_templates.deleted_at IS
  'Soft-delete timestamp (INV-3). NULL = active. Set by application layer; '
  'never hard-deleted. Excluded from all RLS-visible queries.';

-- ── Step 2: Partial index for active rows (hot-path performance) ──────────
--
-- idx_cmt_org_entity (from original migration) covers all rows including
-- soft-deleted. This partial index covers only active rows — the only rows
-- the application ever reads. Query planner prefers this for filtered scans.

CREATE INDEX IF NOT EXISTS idx_cmt_active_org_entity
  ON public.csv_mapping_templates (organization_id, target_entity)
  WHERE deleted_at IS NULL;

-- ── Step 3: RLS policy update ─────────────────────────────────────────────
--
-- USING  — controls which existing rows are visible / modifiable.
--          Adds `deleted_at IS NULL` so soft-deleted rows are invisible to
--          SELECT, UPDATE, and DELETE at the DB level.
--
-- WITH CHECK — controls the new row values after INSERT or UPDATE.
--          Intentionally omits `deleted_at IS NULL` so the soft-delete UPDATE
--          (which sets deleted_at = now()) is not rejected by WITH CHECK.
--          Without this split, the UPDATE that performs the soft-delete would
--          fail: the new row would have deleted_at IS NOT NULL, violating the
--          check. Splitting USING / WITH CHECK is the canonical Postgres pattern
--          for soft-delete under RLS.

DROP POLICY IF EXISTS "CSV mapping template tenant isolation" ON public.csv_mapping_templates;
CREATE POLICY "CSV mapping template tenant isolation"
  ON public.csv_mapping_templates FOR ALL TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID
    AND deleted_at IS NULL
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID
  );
