-- pr_scanner: ignore-regression
-- =============================================================================
-- Stage A.2 — Organization Billing & Contact Fields
-- =============================================================================
-- Adds billing_day (1-28), contact_email, and external_id to organizations.
-- legal_name already exists (20260405000001_super_admin_foundation.sql).
--
-- INV-4: billing_day is a SMALLINT (not money, but constrained for safety).
-- INV-6: No timestamp fields added here — billing cycle is day-of-month only.
-- =============================================================================

-- ── billing_day: day of month for invoice generation (1-28) ──────────────────
-- 28 max avoids February edge cases. NULL = not yet configured.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS billing_day SMALLINT
    CHECK (billing_day BETWEEN 1 AND 28);

-- ── contact_email: primary billing/operational contact ───────────────────────
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS contact_email TEXT;

-- ── external_id: customer ID in external ERP/CRM systems ─────────────────────
-- UNIQUE constraint prevents duplicate mappings.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS external_id TEXT;

-- Unique constraint on external_id (only if not already present)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_organizations_external_id'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT uq_organizations_external_id UNIQUE (external_id);
  END IF;
END $$;

COMMENT ON COLUMN public.organizations.billing_day IS
  'Day of month (1-28) for invoice generation. NULL = not configured.';

COMMENT ON COLUMN public.organizations.contact_email IS
  'Primary billing/operational contact email for this organization.';

COMMENT ON COLUMN public.organizations.external_id IS
  'External ERP/CRM customer identifier. UNIQUE across all organizations.';
