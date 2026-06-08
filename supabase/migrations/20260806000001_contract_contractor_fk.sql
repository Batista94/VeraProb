SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: Normalize Contract → Contractor (client) relationship
--
-- Contracts historically stored the client identity as free text
-- (contractor_name). This formalizes the link with a FK to public.contractors,
-- so a contract is explicitly owned by one of the organization's contractors.
--
-- Strategy (zero-downtime, INV-DB):
--   1. Add nullable contractor_id (FK → contractors). NULLs skip FK validation.
--   2. Backfill: promote each distinct (org, contractor_name) into contractors,
--      then point contracts at the matching contractor.
--   3. contractor_name is RETAINED (soft-deprecate). NOT NULL on contractor_id
--      is deferred to a later cycle once every environment is backfilled.
--
-- INV-1/INV-22: both contracts and contractors are org-scoped; the join never
--               crosses tenants.
-- INV-DB:       additive nullable column + data backfill — no blocking DDL.
-- =============================================================================

-- ── A: Add nullable FK column ─────────────────────────────────────────────────
ALTER TABLE public.contracts
  ADD COLUMN IF NOT EXISTS contractor_id UUID NULL
  REFERENCES public.contractors(id);

-- ── B: Promote distinct contractor_name values into the contractors registry ──
-- contractors.primary_email / contact_name / tax_id are NOT NULL. The backfill
-- supplies deterministic placeholders so existing data is not lost; the synthetic
-- '@placeholder.invalid' email and 'PENDING-' tax_id flag rows that still need
-- human enrichment (tax_id is the CNPJ business key — placeholder, not real).
INSERT INTO public.contractors (organization_id, name, tax_id, primary_email, contact_name)
SELECT DISTINCT
  c.organization_id,
  btrim(c.contractor_name),
  'PENDING-' || substr(md5(c.organization_id::text || '|' || btrim(c.contractor_name)), 1, 14),
  'pending+' || md5(c.organization_id::text || '|' || btrim(c.contractor_name))
    || '@placeholder.invalid',
  btrim(c.contractor_name)
FROM public.contracts c
WHERE c.contractor_name IS NOT NULL
  AND btrim(c.contractor_name) <> ''
ON CONFLICT (organization_id, name) DO NOTHING;

-- ── C: Point each contract at its matching contractor (org-scoped) ────────────
UPDATE public.contracts c
SET contractor_id = ct.id
FROM public.contractors ct
WHERE ct.organization_id = c.organization_id
  AND ct.name = btrim(c.contractor_name)
  AND c.contractor_id IS NULL;

-- ── D: Index for contractor-scoped contract lookups ──────────────────────────
CREATE INDEX IF NOT EXISTS idx_contracts_org_contractor
  ON public.contracts (organization_id, contractor_id);
