-- pr_scanner: ignore-regression
-- INV-6: Add updated_at TIMESTAMPTZ to organizations table.
-- Fixes PostgreSQL error 42703: archive/quota RPCs set updated_at = NOW()
-- but the column did not exist on the organizations table.
--
-- set_updated_at() function already defined in 20260322000002_vehicles_table.sql.

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Backfill existing rows with created_at as a reasonable approximation.
UPDATE public.organizations
SET    updated_at = created_at
WHERE  updated_at IS NULL;

-- Auto-maintain updated_at on every UPDATE.
DROP TRIGGER IF EXISTS trg_organizations_updated_at ON public.organizations;
CREATE TRIGGER trg_organizations_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
