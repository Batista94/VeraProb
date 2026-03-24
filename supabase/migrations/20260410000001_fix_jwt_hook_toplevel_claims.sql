-- Suppress notices from DROP IF EXISTS on fresh reset
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: 20260410000001 — Fix JWT Hook: restore super admin + top-level claims
--
-- This migration supersedes 20260405000001_super_admin_foundation.sql's hook.
--
-- Problem A (regression introduced by this file's first draft):
--   The hook was rewritten without the super_admin_users check, breaking
--   super admin routing — app_metadata.super_admin was never set to true,
--   so lock_screen.dart routed super admins to AdminHome instead of
--   SuperAdminShell.
--
-- Problem B (original bug this migration was created to fix):
--   The hook only injected app_metadata.org_id / app_metadata.role.
--   But RLS policies need auth.jwt() ->> 'organization_id' (top-level — INV-10).
--   The mismatch caused sanction_review_queue SELECT to always return empty.
--
-- Problem C (regression introduced while fixing B):
--   Setting top-level 'role' to 'TENANT_ADMIN' caused PostgreSQL error 22023
--   "role does not exist" — PG reserves the top-level 'role' JWT claim to
--   SET ROLE before query execution. Only DB roles (authenticated, anon, etc.)
--   are valid there. Application roles MUST stay in app_metadata only.
--   RLS policies were updated in 20260410000002 to read app_metadata.role.
--
-- Fix: full hook with THREE priority layers:
--   1. Super admin check (super_admin_users) → app_metadata.super_admin=true,
--      nullify tenant claims, RETURN early.
--   2. Tenant role check (user_roles) → inject top-level organization_id (INV-10)
--      AND full app_metadata claims (for Flutter auth_providers._jwtAppMeta).
--      Do NOT inject top-level 'role'. INV-20 contractor_id logic preserved.
--   3. ELSE → deny all context via app_metadata; do NOT set top-level 'role'
--      to null — Supabase schema validation requires it to be a string.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  claims      jsonb;
  user_role   record;
  is_super    boolean := false;
BEGIN
  claims := event->'claims';

  -- ── 1. SUPER ADMIN CHECK (runs before user_roles — defense-in-depth) ────────
  SELECT true INTO is_super
    FROM public.super_admin_users
   WHERE user_id = (event->>'user_id')::uuid;

  IF FOUND THEN
    -- Inject super_admin claim; nullify all tenant-scoped claims.
    claims := jsonb_set(claims, '{app_metadata, super_admin}',   'true'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    RETURN jsonb_set(event, '{claims}', claims);
  END IF;

  -- ── 2. TENANT ROLE LOOKUP ────────────────────────────────────────────────────
  SELECT ur.organization_id, ur.role, ur.contractor_id
    INTO user_role
    FROM public.user_roles ur
   WHERE ur.user_id = (event->>'user_id')::uuid;

  IF FOUND THEN
    -- Top-level claim: consumed by all RLS policies (INV-10).
    -- auth.jwt() ->> 'organization_id'
    -- NOTE: Do NOT inject top-level 'role' — PostgreSQL reserves it as a
    -- database role name (SET ROLE). Injecting 'TENANT_ADMIN' here causes
    -- error 22023. Application role lives in app_metadata only.
    claims := jsonb_set(claims, '{organization_id}',
                        to_jsonb(user_role.organization_id::text));

    -- app_metadata: consumed by Flutter auth_providers._jwtAppMeta
    claims := jsonb_set(claims, '{app_metadata, org_id}',
                        to_jsonb(user_role.organization_id));
    claims := jsonb_set(claims, '{app_metadata, role}',
                        to_jsonb(user_role.role));

    -- INV-20: CONTRACTOR_VIEWER requires dual-key isolation.
    IF user_role.role = 'CONTRACTOR_VIEWER' THEN
      claims := jsonb_set(claims, '{app_metadata, contractor_id}',
                          to_jsonb(user_role.contractor_id));
    ELSE
      claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    END IF;
  ELSE
    -- User not found in either table (pending invite, edge case).
    -- Do NOT override top-level 'role' — Supabase requires it to be a string.
    -- Only mark app_metadata so Flutter knows this session has no tenant context.
    claims := jsonb_set(claims, '{app_metadata, super_admin}',   'false'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
  END IF;

  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;
