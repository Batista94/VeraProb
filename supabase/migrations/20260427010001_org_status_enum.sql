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
-- super_admin_tenant_health_view depends on is_active → must drop view first,
-- then drop the column, then recreate both. The view definition is unchanged
-- because is_active will still exist (as a GENERATED column).
DROP VIEW IF EXISTS public.super_admin_tenant_health_view;

ALTER TABLE public.organizations
  DROP COLUMN IF EXISTS is_active;

ALTER TABLE public.organizations
  ADD COLUMN is_active BOOLEAN GENERATED ALWAYS AS (status = 'ACTIVE') STORED;

-- Recreate the view — now reads generated is_active (retro-compatible).
CREATE OR REPLACE VIEW public.super_admin_tenant_health_view AS
SELECT
  o.id,
  o.name,
  o.legal_name,
  o.plan_type,
  o.is_active,
  o.status,
  o.max_vehicles,
  o.max_active_contracts,
  COUNT(DISTINCT c.id)
    FILTER (WHERE c.status = 'active')                     AS active_contract_count,
  MAX(cf.gps_timestamp)                                    AS last_telemetry_at,
  COUNT(DISTINCT a.id)
    FILTER (WHERE a.severity = 'CRITICAL' AND a.resolved_at_utc IS NULL)
                                                           AS open_critical_alert_count
FROM public.organizations o
LEFT JOIN public.contracts c
  ON c.organization_id = o.id
LEFT JOIN public.canonical_facts cf
  ON cf.organization_id = o.id
LEFT JOIN public.operational_alerts a
  ON a.organization_id = o.id
GROUP BY o.id;

-- Intentionally NO GRANT to authenticated or anon.
-- service_role bypasses RLS and view-level grants automatically.

-- ── Step 4: Index for status filtering (SuperAdmin dashboard) ────────────────
CREATE INDEX IF NOT EXISTS idx_organizations_status
  ON public.organizations (status);

-- ── Step 5: Update plan_type CHECK to include status-aware validation ────────
COMMENT ON COLUMN public.organizations.status IS
  'Organization lifecycle: TRIAL → ACTIVE → SUSPENDED → CHURNED → DELETED. '
  'is_active is a generated column derived from this field for retro-compatibility.';

COMMENT ON COLUMN public.organizations.is_active IS
  'GENERATED ALWAYS AS (status = ''ACTIVE''). Retro-compatible with existing RLS and app code.';
