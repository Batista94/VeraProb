-- =============================================================================
-- Stage A.6 — Quota Soft Limits & Warning System
-- =============================================================================
-- Creates org_quota_warnings table and a trigger on vehicles INSERT that
-- emits warnings at 50%, 80%, 90%, and 99% usage thresholds.
--
-- This is a SOFT limit system — it does NOT block inserts. The existing
-- hard limit (P0001 RAISE EXCEPTION) in the application layer remains
-- the enforcement mechanism.
--
-- INV-10: Error Visibility — warnings are visible in the dashboard.
-- INV-1:  org_id filter ALL — warnings are per-org.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.org_quota_warnings (
  id               BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id  UUID        NOT NULL REFERENCES public.organizations(id),
  resource         TEXT        NOT NULL,
  usage_pct        SMALLINT    NOT NULL CHECK (usage_pct BETWEEN 0 AND 100),
  threshold        SMALLINT    NOT NULL CHECK (threshold IN (50, 80, 90, 99)),
  current_count    INT         NOT NULL,
  max_allowed      INT         NOT NULL,
  triggered_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Prevent duplicate warnings for the same org/resource/threshold
  CONSTRAINT uq_org_quota_warning_active
    UNIQUE (organization_id, resource, threshold)
);

-- ── Trigger: emit quota warnings on vehicles INSERT ──────────────────────────
CREATE OR REPLACE FUNCTION public.check_vehicle_quota_warning()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_vehicles INT;
  v_current_count INT;
  v_usage_pct INT;
  v_thresholds INT[] := ARRAY[50, 80, 90, 99];
  v_threshold INT;
BEGIN
  -- Get org's max_vehicles limit
  SELECT max_vehicles INTO v_max_vehicles
  FROM public.organizations
  WHERE id = NEW.organization_id;

  -- If no limit set (NULL = unlimited), skip
  IF v_max_vehicles IS NULL OR v_max_vehicles = 0 THEN
    RETURN NEW;
  END IF;

  -- Count current active vehicles (excluding retired)
  SELECT COUNT(*) INTO v_current_count
  FROM public.vehicles
  WHERE organization_id = NEW.organization_id
    AND status != 'retired';

  -- Calculate usage percentage
  v_usage_pct := (v_current_count * 100) / v_max_vehicles;

  -- Check each threshold and emit warning if crossed
  FOREACH v_threshold IN ARRAY v_thresholds LOOP
    IF v_usage_pct >= v_threshold THEN
      INSERT INTO public.org_quota_warnings (
        organization_id, resource, usage_pct, threshold,
        current_count, max_allowed, triggered_at
      )
      VALUES (
        NEW.organization_id, 'vehicles', v_usage_pct, v_threshold,
        v_current_count, v_max_vehicles, NOW()
      )
      ON CONFLICT (organization_id, resource, threshold)
      DO UPDATE SET
        usage_pct = EXCLUDED.usage_pct,
        current_count = EXCLUDED.current_count,
        max_allowed = EXCLUDED.max_allowed,
        triggered_at = EXCLUDED.triggered_at;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vehicle_quota_warning ON public.vehicles;
CREATE TRIGGER trg_vehicle_quota_warning
  AFTER INSERT ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.check_vehicle_quota_warning();

-- ── Cleanup trigger: remove warnings when vehicles are retired ───────────────
CREATE OR REPLACE FUNCTION public.recalc_vehicle_quota_warning_on_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_vehicles INT;
  v_current_count INT;
  v_usage_pct INT;
BEGIN
  -- Only recalculate if status changed to 'retired'
  IF NEW.status = 'retired' AND OLD.status != 'retired' THEN
    SELECT max_vehicles INTO v_max_vehicles
    FROM public.organizations
    WHERE id = NEW.organization_id;

    IF v_max_vehicles IS NULL OR v_max_vehicles = 0 THEN
      RETURN NEW;
    END IF;

    SELECT COUNT(*) INTO v_current_count
    FROM public.vehicles
    WHERE organization_id = NEW.organization_id
      AND status != 'retired';

    v_usage_pct := (v_current_count * 100) / v_max_vehicles;

    -- Remove warnings for thresholds no longer exceeded
    DELETE FROM public.org_quota_warnings
    WHERE organization_id = NEW.organization_id
      AND resource = 'vehicles'
      AND threshold > v_usage_pct;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_vehicle_quota_warning_update ON public.vehicles;
CREATE TRIGGER trg_vehicle_quota_warning_update
  AFTER UPDATE ON public.vehicles
  FOR EACH ROW EXECUTE FUNCTION public.recalc_vehicle_quota_warning_on_update();

-- ── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_org_quota_warnings_org_resource
  ON public.org_quota_warnings (organization_id, resource);

-- ── RLS ──────────────────────────────────────────────────────────────────────
ALTER TABLE public.org_quota_warnings ENABLE ROW LEVEL SECURITY;

-- Org admins can see their own warnings
CREATE POLICY "Tenant Isolation: org_quota_warnings" ON public.org_quota_warnings
  FOR SELECT
  TO authenticated
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  );

-- INSERT/UPDATE/DELETE only via service_role (triggers run as SECURITY DEFINER)
-- No INSERT/UPDATE/DELETE policies for authenticated = deny direct writes.

COMMENT ON TABLE public.org_quota_warnings IS
  'Soft limit warnings emitted at 50/80/90/99% usage thresholds. '
  'Does NOT block operations — purely informational for dashboard display.';
