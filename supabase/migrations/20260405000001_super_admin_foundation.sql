-- =============================================================================
-- Phase 9.2 — SuperAdmin Foundation (INV-22: Lead Reviewer [GO] required)
-- =============================================================================
-- D1: super_admin_users is a dedicated table — user_roles requires org_id NOT NULL.
-- D2: JWT hook extended — super_admin check runs BEFORE user_roles lookup.
-- INV-10: RLS Tenant Claim uses auth.jwt() -> 'app_metadata'.
-- =============================================================================


-- =============================================================================
-- A. super_admin_users TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.super_admin_users (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE,
  email      TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- No RLS for authenticated — deny by default.
-- supabase_auth_admin reads this table from the hook (SECURITY DEFINER context).
ALTER TABLE public.super_admin_users ENABLE ROW LEVEL SECURITY;

-- Grant table-level access to supabase_auth_admin for the JWT hook.
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT SELECT ON TABLE public.super_admin_users TO supabase_auth_admin;


-- =============================================================================
-- B. organizations TABLE — 5 new columns
-- =============================================================================

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS legal_name           TEXT,
  ADD COLUMN IF NOT EXISTS cnpj                 TEXT,
  ADD COLUMN IF NOT EXISTS plan_type            TEXT NOT NULL DEFAULT 'starter'
    CHECK (plan_type IN ('starter', 'professional', 'enterprise')),
  ADD COLUMN IF NOT EXISTS max_vehicles         INT  NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS max_active_contracts INT  NOT NULL DEFAULT 10;


-- =============================================================================
-- C. custom_access_token_hook — extends 20260402000002
-- SuperAdmin check runs FIRST; falls through to existing user_roles logic if not found.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  claims      jsonb;
  user_role   record;
  is_super    boolean := false;
BEGIN
  claims := event->'claims';

  -- ── SUPER ADMIN CHECK (runs before user_roles — D2) ──────────────────────
  SELECT true INTO is_super
    FROM public.super_admin_users
   WHERE user_id = (event->>'user_id')::uuid;

  IF FOUND THEN
    -- Inject super_admin claim; nullify all tenant-scoped claims (defense-in-depth).
    claims := jsonb_set(claims, '{app_metadata, super_admin}',   'true'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    RETURN jsonb_set(event, '{claims}', claims);
  END IF;

  -- ── TENANT ROLE LOOKUP (unchanged from 20260402000002) ───────────────────
  SELECT ur.organization_id, ur.role, ur.contractor_id
    INTO user_role
    FROM public.user_roles ur
   WHERE ur.user_id = (event->>'user_id')::uuid;

  IF FOUND THEN
    claims := jsonb_set(claims, '{app_metadata, org_id}',
                        to_jsonb(user_role.organization_id));
    claims := jsonb_set(claims, '{app_metadata, role}',
                        to_jsonb(user_role.role));

    IF user_role.role = 'CONTRACTOR_VIEWER' THEN
      claims := jsonb_set(claims, '{app_metadata, contractor_id}',
                          to_jsonb(user_role.contractor_id));
    ELSE
      -- INV-20: explicit NULL for all internal roles.
      claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    END IF;
  ELSE
    -- User not found in either table — deny all context.
    claims := jsonb_set(claims, '{app_metadata, super_admin}',   'false'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
  END IF;

  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;
