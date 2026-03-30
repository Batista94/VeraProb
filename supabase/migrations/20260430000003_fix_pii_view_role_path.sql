-- Migration: 20260430000003_fix_pii_view_role_path.sql
-- 
-- Fix: PII views (contractors_view, invitations_view) were failing role checks
-- due to 'get_auth_role()' being SECURITY DEFINER (ignoring caller's JWT).
-- Switching to SECURITY INVOKER (default) ensures the function correctly
-- extracts the role from the active authenticated session's JWT.
--
-- Re-remedies LGPD Breach (INV-32) and UX Degradation for Admins.

BEGIN;

-- 1. Helper function for consistent role extraction (INVOKER context)
CREATE OR REPLACE FUNCTION public.get_auth_role()
RETURNS TEXT
LANGUAGE sql STABLE
AS $$
  -- Layer 1: Try Supabase auth.jwt()
  -- Layer 2: Try direct request.jwt.claims (fallback)
  SELECT COALESCE(
    (auth.jwt() -> 'app_metadata' ->> 'role'),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb -> 'app_metadata' ->> 'role'),
    'NO_ROLE'
  )
$$;

-- 2. Refresh contractors_view
CREATE OR REPLACE VIEW public.contractors_view
WITH (security_invoker = true)
AS
SELECT
  id,
  organization_id,
  name,
  contact_name,
  created_at_utc,
  
  CASE (public.get_auth_role())
    WHEN 'TENANT_ADMIN' THEN tax_id
    WHEN 'AUDITOR'      THEN tax_id
    ELSE                     public.mask_cnpj(tax_id)
  END AS tax_id,

  CASE (public.get_auth_role())
    WHEN 'TENANT_ADMIN' THEN primary_email
    WHEN 'AUDITOR'      THEN primary_email
    ELSE                     public.mask_email(primary_email)
  END AS primary_email

FROM public.contractors;

-- 3. Refresh invitations_view
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

  CASE (public.get_auth_role())
    WHEN 'TENANT_ADMIN' THEN email
    ELSE                     public.mask_email(email)
  END AS email

FROM public.invitations;

COMMIT;
