-- =============================================================================
-- Migration: 20260414000001 — JWT Hook: guard against JSON null app_metadata
--
-- Problem: custom_access_token_hook calls
--   jsonb_set(claims, '{app_metadata, super_admin}', ...)
-- If claims->'app_metadata' is JSON null (not SQL NULL), PostgreSQL cannot
-- navigate the nested path and throws an internal error, causing the hook to
-- return HTTP 500 instead of the expected 400 (unauthorized) or valid token.
-- This broke Test 1116 (JWT Hook E2E) with "JSONB Parse Error / 500".
--
-- Fix: after extracting claims, check if app_metadata is absent or JSON null
-- and if so initialize it to an empty object before any nested jsonb_set call.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  claims      jsonb;
  user_role   record;
  is_super    boolean := false;
BEGIN
  claims := event->'claims';

  -- Guard: ensure app_metadata is a JSON object before any nested jsonb_set.
  -- If it is absent or JSON null, initialize to empty object to prevent
  -- "cannot set path in scalar" internal error (Test 1116 regression).
  IF claims->'app_metadata' IS NULL
     OR jsonb_typeof(claims->'app_metadata') != 'object' THEN
    claims := jsonb_set(claims, '{app_metadata}', '{}'::jsonb, true);
  END IF;

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
