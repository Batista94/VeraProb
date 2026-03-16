-- ============================================================
-- PactaFlow — Phase 6: Contractors Table
-- ============================================================
-- REASON:
--   Introduce the Contractor aggregate to support dedicated
--   ownership of operational zones and future review flows.
-- ============================================================

CREATE TABLE public.contractors (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID        NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  name            TEXT        NOT NULL,
  tax_id          TEXT,
  primary_email   TEXT        NOT NULL,
  contact_name    TEXT        NOT NULL,
  created_at_utc  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Ensure contractor names are unique per organization
  CONSTRAINT uq_contractor_name_per_org UNIQUE (organization_id, name)
);

-- Performance: Filter by organization
CREATE INDEX idx_contractors_organization ON public.contractors (organization_id);

-- RLS: Contractor Isolation
ALTER TABLE public.contractors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant Isolation: contractors"
  ON public.contractors
  FOR ALL TO authenticated
  USING     (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
  WITH CHECK (organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);
