-- =============================================================================
-- Phase 8.1.3 — CONTRACTOR_VIEWER Dual-Key RLS (INV-20)
-- =============================================================================
-- PREREQUISITE: 20260402000001_fix_audit_packages_jwt_path.sql MUST be applied first.
--
-- WHAT THIS MIGRATION DOES:
--   A. Extends user_roles: adds CONTRACTOR_VIEWER role + contractor_id column
--      with a CHECK that enforces dual-key presence at insert time.
--   B. Extends audit_packages: adds denormalized contractor_id for RLS efficiency.
--   C. Updates custom_access_token_hook: injects contractor_id into JWT.
--      Internal roles (TENANT_ADMIN, OPERATOR, AUDITOR) receive explicit NULL
--      to prevent accidental privilege escalation (hostile-defense-attorney veto).
--   D. Replaces audit_packages RLS with two policies:
--      - Internal roles: org isolation + contractor_id IS NULL guard
--      - CONTRACTOR_VIEWER: dual-key (org + contractor) + sealed-only
--
-- INV-20: CONTRACTOR_VIEWER DUAL-KEY ISOLATION
-- INV-16: CONTRACTOR_VIEWER never sees draft packages (RLS-enforced, not app-layer)
-- =============================================================================


-- =============================================================================
-- A. EXTEND user_roles
-- =============================================================================

-- 1. Drop existing CHECK constraint (needs to allow CONTRACTOR_VIEWER)
ALTER TABLE public.user_roles
  DROP CONSTRAINT IF EXISTS user_roles_role_check;

-- 2. Re-add with CONTRACTOR_VIEWER included
ALTER TABLE public.user_roles
  ADD CONSTRAINT user_roles_role_check
    CHECK (role IN ('TENANT_ADMIN', 'OPERATOR', 'AUDITOR', 'CONTRACTOR_VIEWER'));

-- 3. Add contractor_id column (NULL for internal roles)
ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS contractor_id UUID REFERENCES public.contractors(id);

-- 4. Enforce dual-key invariant at schema level:
--    CONTRACTOR_VIEWER must have contractor_id; all other roles must not.
ALTER TABLE public.user_roles
  ADD CONSTRAINT contractor_viewer_requires_contractor_id
    CHECK (
      (role = 'CONTRACTOR_VIEWER' AND contractor_id IS NOT NULL) OR
      (role <> 'CONTRACTOR_VIEWER' AND contractor_id IS NULL)
    );


-- =============================================================================
-- B. EXTEND audit_packages — denormalized contractor_id for RLS performance
-- =============================================================================
-- NOTE: audit_packages has a CREATE RULE that blocks UPDATE/DELETE (INV-1).
--       ALTER TABLE (DDL) is not affected by DML rules — safe to execute.

ALTER TABLE public.audit_packages
  ADD COLUMN IF NOT EXISTS contractor_id UUID REFERENCES public.contractors(id);

-- Partial index: only index non-null contractor packages (contractor portal queries)
CREATE INDEX IF NOT EXISTS idx_audit_packages_contractor
  ON public.audit_packages(organization_id, contractor_id)
  WHERE contractor_id IS NOT NULL;


-- =============================================================================
-- C. UPDATE custom_access_token_hook — inject contractor_id claim
-- =============================================================================

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  claims    jsonb;
  user_role record;
BEGIN
  -- Fetch role context including new contractor_id column
  SELECT ur.organization_id, ur.role, ur.contractor_id
    INTO user_role
    FROM public.user_roles ur
   WHERE ur.user_id = (event->>'user_id')::uuid;

  claims := event->'claims';

  IF FOUND THEN
    claims := jsonb_set(claims, '{app_metadata, org_id}',
                        to_jsonb(user_role.organization_id));
    claims := jsonb_set(claims, '{app_metadata, role}',
                        to_jsonb(user_role.role));

    IF user_role.role = 'CONTRACTOR_VIEWER' THEN
      -- Inject contractor scope for dual-key RLS
      claims := jsonb_set(claims, '{app_metadata, contractor_id}',
                          to_jsonb(user_role.contractor_id));
    ELSE
      -- INV-20: explicit NULL for all internal roles — prevents accidental escalation
      -- even if contractor_id column were somehow populated for an internal user.
      claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    END IF;
  ELSE
    -- User not found in user_roles — deny all context
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
  END IF;

  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;


-- =============================================================================
-- D. REPLACE audit_packages RLS policies (dual-policy strategy)
-- =============================================================================
-- The policy from 8.1.4 covers ALL roles with a single predicate.
-- We replace it with two targeted policies with stronger guarantees.

DROP POLICY IF EXISTS "audit_packages_tenant_isolation" ON public.audit_packages;

-- Policy 1: Internal roles (TENANT_ADMIN, OPERATOR, AUDITOR)
-- Extra guard: contractor_id in JWT must be NULL.
-- This is redundant with the hook logic but provides defense-in-depth (INV-20).
CREATE POLICY "audit_packages_internal_roles"
  ON public.audit_packages
  FOR ALL
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  )
  WITH CHECK (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND (auth.jwt() -> 'app_metadata' ->> 'contractor_id') IS NULL
  );

-- Policy 2: CONTRACTOR_VIEWER — dual-key isolation (INV-20)
-- Only SELECT (read-only portal). Only 'sealed' packages (INV-16 + INV-20).
-- RLS enforces sealed-only at DB level — not relying on app-layer filtering.
CREATE POLICY "audit_packages_contractor_viewer_isolation"
  ON public.audit_packages
  FOR SELECT
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND contractor_id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
    AND status = 'sealed'
  );


-- =============================================================================
-- VERIFICATION STEPS (run after applying in Supabase SQL Editor):
--
-- 1. Test CONTRACTOR_VIEWER constraint:
--    INSERT INTO user_roles (user_id, organization_id, role)
--    VALUES (gen_random_uuid(), gen_random_uuid(), 'CONTRACTOR_VIEWER');
--    → Should FAIL: violates contractor_viewer_requires_contractor_id
--
-- 2. Test internal role constraint:
--    INSERT INTO user_roles (user_id, organization_id, role, contractor_id)
--    VALUES (gen_random_uuid(), gen_random_uuid(), 'OPERATOR', gen_random_uuid());
--    → Should FAIL: violates contractor_viewer_requires_contractor_id
--
-- 3. As CONTRACTOR_VIEWER JWT: SELECT * FROM audit_packages
--    → Should return only sealed packages for their contractor_id
--
-- 4. As admin JWT: SELECT * FROM audit_packages
--    → Should return all packages for their org (draft + sealed)
-- =============================================================================
