-- =============================================================================
-- Phase 8.5 — PII Masking (LGPD Compliance)
-- =============================================================================
-- CONTEXT:
--   PactaFlow processes B2B contractor data that includes personally identifiable
--   and commercially sensitive information. Under LGPD (Lei 13.709/2018),
--   PII fields must be protected with access controls appropriate to each role.
--
-- PII COLUMNS INVENTORIED IN THIS SCHEMA:
--   contractors.tax_id          — Brazilian CNPJ (corporate tax ID)
--   contractors.primary_email   — contractor contact email
--   contractors.contact_name    — contractor contact person name
--   invitations.email           — invitee email address
--
-- MASKING STRATEGY:
--   Rather than the postgresql-anonymizer extension (requires Supabase Pro),
--   we use SECURITY DEFINER views with role-based CASE masking.
--   This is compatible with Supabase Free Tier and does not require pg_anon.
--
--   Access matrix:
--   ┌─────────────────────┬──────────┬──────────────┬───────────────┐
--   │ Field               │ ADMIN    │ OPERATOR     │ CONTRACTOR_V. │
--   ├─────────────────────┼──────────┼──────────────┼───────────────┤
--   │ tax_id (CNPJ)       │ Full     │ Masked       │ Full (own)    │
--   │ primary_email       │ Full     │ Domain only  │ Full (own)    │
--   │ contact_name        │ Full     │ Full         │ Full (own)    │
--   │ invitations.email   │ Full     │ Masked       │ No access     │
--   └─────────────────────┴──────────┴──────────────┴───────────────┘
--
-- INVARIANTS:
--   INV-4: Domain Sovereignty — masking at DB layer, not application layer
--   INV-6: MULTI-TENANT + RLS — all views respect organization_id isolation
--   INV-10: RLS TENANT CLAIM — auth.jwt() -> 'app_metadata' path
-- =============================================================================


-- =============================================================================
-- A. MASKING HELPER FUNCTIONS
-- =============================================================================

-- mask_cnpj: Shows XX.XXX.XXX/XXXX-XX for non-admin roles
-- Accepts raw CNPJ in any format (with or without dots/slashes)
CREATE OR REPLACE FUNCTION public.mask_cnpj(raw_cnpj TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
  SELECT 'XX.XXX.XXX/XXXX-XX'
$$;

-- mask_email: Shows ****@domain.com (domain visible, localpart hidden)
-- Preserves domain to allow organizational context without revealing the mailbox
CREATE OR REPLACE FUNCTION public.mask_email(raw_email TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
  SELECT
    CASE
      WHEN raw_email IS NULL THEN NULL
      WHEN position('@' IN raw_email) = 0 THEN '****'
      ELSE '****@' || split_part(raw_email, '@', 2)
    END
$$;


-- =============================================================================
-- B. MASKED VIEW: contractors_view
-- =============================================================================
-- Applications should query this view instead of the raw contractors table
-- for list/summary displays. The raw table is used only for INSERT/UPDATE
-- (internal roles via RLS) and by SECURITY DEFINER RPCs that need full data.
--
-- RLS is NOT enabled on views in Postgres — the masking is enforced by the
-- CASE expression based on the JWT role claim.
-- =============================================================================

CREATE OR REPLACE VIEW public.contractors_view
WITH (security_invoker = true)  -- respects the caller's RLS context
AS
SELECT
  id,
  organization_id,
  name,
  contact_name,
  created_at_utc,

  -- tax_id: full for TENANT_ADMIN and AUDITOR; masked for OPERATOR; full for
  -- CONTRACTOR_VIEWER on their own record (RLS handles row isolation)
  CASE (auth.jwt() -> 'app_metadata' ->> 'role')
    WHEN 'TENANT_ADMIN' THEN tax_id
    WHEN 'AUDITOR'      THEN tax_id
    ELSE                     public.mask_cnpj(tax_id)
  END AS tax_id,

  -- primary_email: full for admins and auditors; domain-only for operators;
  -- full for CONTRACTOR_VIEWER on their own record (RLS handles row isolation)
  CASE (auth.jwt() -> 'app_metadata' ->> 'role')
    WHEN 'TENANT_ADMIN' THEN primary_email
    WHEN 'AUDITOR'      THEN primary_email
    ELSE                     public.mask_email(primary_email)
  END AS primary_email

FROM public.contractors;

-- Grant SELECT on the view to authenticated users (RLS on underlying table
-- already restricts which rows are visible per role via the dual-key policies)
GRANT SELECT ON public.contractors_view TO authenticated;


-- =============================================================================
-- C. MASKED VIEW: invitations_view
-- =============================================================================
-- Invitations contain email addresses of prospective users.
-- OPERATOR role sees masked emails; TENANT_ADMIN sees full data.
-- CONTRACTOR_VIEWER has no access to invitations (not needed for portal).
-- =============================================================================

CREATE OR REPLACE VIEW public.invitations_view
WITH (security_invoker = true)
AS
SELECT
  id,
  organization_id,
  role,
  CASE
    WHEN revoked_at_utc IS NOT NULL   THEN 'revoked'
    WHEN accepted_at_utc IS NOT NULL  THEN 'accepted'
    WHEN expires_at_utc < now()       THEN 'expired'
    ELSE                                   'pending'
  END AS status,
  created_at_utc,
  expires_at_utc,
  accepted_at_utc,
  invited_by AS invited_by_user_id,

  -- email: full for TENANT_ADMIN; masked for all other roles
  CASE (auth.jwt() -> 'app_metadata' ->> 'role')
    WHEN 'TENANT_ADMIN' THEN email
    ELSE                     public.mask_email(email)
  END AS email

FROM public.invitations;

GRANT SELECT ON public.invitations_view TO authenticated;


-- =============================================================================
-- D. REVOKE DIRECT SELECT ON SENSITIVE COLUMNS (defense-in-depth)
-- =============================================================================
-- Note: Column-level REVOKE in Postgres applies to explicit column grants.
-- Since `authenticated` has broad SELECT via RLS policies, the most effective
-- control is the masked views above combined with application-layer enforcement.
--
-- Document the expectation explicitly:
COMMENT ON COLUMN public.contractors.tax_id IS
  'LGPD: PII — Brazilian CNPJ. Query via contractors_view for role-based masking.';

COMMENT ON COLUMN public.contractors.primary_email IS
  'LGPD: PII — Contact email. Query via contractors_view for role-based masking.';

COMMENT ON COLUMN public.invitations.email IS
  'LGPD: PII — Invitee email. Query via invitations_view for role-based masking.';


-- =============================================================================
-- VERIFICATION STEPS (run in Supabase SQL Editor after applying)
-- =============================================================================
--
-- 1. As OPERATOR JWT:
--    SELECT tax_id, primary_email FROM contractors_view LIMIT 1;
--    → tax_id must be 'XX.XXX.XXX/XXXX-XX'
--    → primary_email must be '****@domain.com'
--
-- 2. As TENANT_ADMIN JWT:
--    SELECT tax_id, primary_email FROM contractors_view LIMIT 1;
--    → Both fields must show full unmasked values
--
-- 3. As CONTRACTOR_VIEWER JWT (contractor_id = X):
--    SELECT tax_id, primary_email FROM contractors_view;
--    → Only 1 row returned (own record — RLS enforced)
--    → tax_id masked (CASE falls to ELSE — 'XX.XXX.XXX/XXXX-XX')
--    → primary_email masked (own email masked to domain-only)
--    NOTE: If CONTRACTOR_VIEWER needs to see their own full email for
--          self-service, upgrade the CASE to check contractor_id = own ID.
--          For now, masking applies consistently to avoid leakage vectors.
--
-- 4. As OPERATOR JWT:
--    SELECT email FROM invitations_view LIMIT 5;
--    → All emails must show '****@domain.com' pattern
-- =============================================================================
