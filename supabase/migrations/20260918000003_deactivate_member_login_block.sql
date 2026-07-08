-- =============================================================================
-- Migration: 20260918000003 — Deactivate Member Login Block
--
-- CONTEXT: 
-- Bug 1 Fix. deactivate_member previously only set user_roles.is_active=false, 
-- but did not block login at the GoTrue layer. Furthermore, the 
-- custom_access_token_hook didn't filter by is_active=true.
--
-- This migration updates deactivate_member to apply a banned_until='infinity'
-- at the auth.users layer and revokes active sessions. It also updates 
-- reactivate_member to clear the ban. Lastly, it enforces is_active=true in the 
-- JWT hook as defense in depth.
--
-- CIA Triad: Confidentiality (blocks access for inactive users).
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── 1. Update deactivate_member ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.deactivate_member(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_org   UUID;
  v_target_org   UUID;
  v_target_role  TEXT;
  v_target_email TEXT;
  v_admin_count  INT;
BEGIN
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID;

  SELECT organization_id, role, user_email INTO v_target_org, v_target_role, v_target_email
  FROM user_roles WHERE user_id = p_target_user_id AND is_active = true;

  IF NOT FOUND OR v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'P0002';
  END IF;

  IF p_target_user_id = (auth.jwt() ->> 'sub')::uuid THEN
    RAISE EXCEPTION 'Cannot deactivate yourself' USING ERRCODE = 'P0001';
  END IF;

  IF v_target_role = 'TENANT_ADMIN' THEN
    SELECT COUNT(*) INTO v_admin_count FROM user_roles
    WHERE organization_id = v_caller_org AND role = 'TENANT_ADMIN' AND is_active = true;
    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot deactivate the last administrator' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- 1. Soft delete the role
  UPDATE user_roles SET is_active = false WHERE user_id = p_target_user_id;

  -- 2. Apply GoTrue ban
  UPDATE auth.users SET banned_until = 'infinity' WHERE id = p_target_user_id;

  -- 3. Revoke active sessions
  PERFORM public.revoke_user_sessions(p_target_user_id);

  -- 4. Audit
  PERFORM public._rbac_audit(
    'MEMBER_DEACTIVATED',
    jsonb_build_object('target_user', p_target_user_id, 'target_email', v_target_email)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deactivate_member(UUID) TO authenticated;

-- ── 2. Update reactivate_member ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reactivate_member(p_target_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
DECLARE
  v_caller_org   UUID;
  v_target_org   UUID;
  v_target_email TEXT;
BEGIN
  v_caller_org := (auth.jwt() -> 'app_metadata' ->> 'org_id')::UUID;

  SELECT organization_id, user_email INTO v_target_org, v_target_email
  FROM user_roles WHERE user_id = p_target_user_id;

  IF NOT FOUND OR v_target_org <> v_caller_org THEN
    RAISE EXCEPTION 'Member not found' USING ERRCODE = 'P0002';
  END IF;

  -- 1. Restore the role
  UPDATE user_roles SET is_active = true WHERE user_id = p_target_user_id;

  -- 2. Remove GoTrue ban
  UPDATE auth.users SET banned_until = NULL WHERE id = p_target_user_id;

  -- 3. Audit
  PERFORM public._rbac_audit(
    'MEMBER_REACTIVATED',
    jsonb_build_object('target_user', p_target_user_id, 'target_email', v_target_email)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reactivate_member(UUID) TO authenticated;

-- ── 3. Update custom_access_token_hook ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  claims       jsonb;
  user_role    record;
  is_super     boolean := false;
  v_perms      jsonb;
  v_scopes     jsonb;
  v_perms_v    bigint;
  v_user_id    uuid;
BEGIN
  claims    := event->'claims';
  v_user_id := (event->>'user_id')::uuid;

  IF claims->'app_metadata' IS NULL
     OR jsonb_typeof(claims->'app_metadata') != 'object' THEN
    claims := jsonb_set(claims, '{app_metadata}', '{}'::jsonb, true);
  END IF;

  -- ── 1. SUPER ADMIN (sovereign — bypass tenant RBAC) ───────────────────────
  SELECT true INTO is_super
    FROM public.super_admin_users
   WHERE user_id = v_user_id;

  IF FOUND THEN
    claims := jsonb_set(claims, '{app_metadata, super_admin}',   'true'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, permissions}',   '["*"]'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, perm_scopes}',   '{}'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, perms_v}',       '0'::jsonb);
    RETURN jsonb_set(event, '{claims}', claims);
  END IF;

  -- ── 2. TENANT ROLE LOOKUP (coarse trust root — unchanged) ─────────────────
  SELECT ur.organization_id, ur.role, ur.contractor_id
    INTO user_role
    FROM public.user_roles ur
   WHERE ur.user_id = v_user_id
     AND ur.is_active = true;

  IF FOUND THEN
    claims := jsonb_set(claims, '{organization_id}',
                        to_jsonb(user_role.organization_id::text));
    claims := jsonb_set(claims, '{app_metadata, org_id}',
                        to_jsonb(user_role.organization_id));
    claims := jsonb_set(claims, '{app_metadata, role}',
                        to_jsonb(user_role.role));

    IF user_role.role = 'CONTRACTOR_VIEWER' THEN
      claims := jsonb_set(claims, '{app_metadata, contractor_id}',
                          to_jsonb(user_role.contractor_id));
    ELSE
      claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    END IF;

    -- ── 3. FINE-GRAINED PERMISSIONS (additive layer) ────────────────────────
    IF user_role.role = 'TENANT_ADMIN' THEN
      v_perms   := '["*"]'::jsonb;
      v_scopes  := '{}'::jsonb;
      v_perms_v := 0;
    ELSE
      -- Distinct permission keys from all active, non-expired custom roles.
      SELECT COALESCE(
        (SELECT jsonb_agg(sub.key ORDER BY sub.key)
           FROM (
             SELECT DISTINCT trp.permission_key AS key
               FROM public.user_tenant_roles utr
               JOIN public.tenant_roles tr
                 ON tr.id = utr.tenant_role_id
                AND tr.deleted_at IS NULL
               JOIN public.tenant_role_permissions trp
                 ON trp.tenant_role_id = utr.tenant_role_id
              WHERE utr.user_id = v_user_id
                AND utr.organization_id = user_role.organization_id
                AND utr.revoked_at IS NULL
                AND utr.valid_from <= NOW()
                AND (utr.valid_until IS NULL OR utr.valid_until > NOW())
           ) AS sub),
        '[]'::jsonb
      )
        INTO v_perms;

      -- ABAC-lite: union scoped resource IDs per permission key.
      SELECT COALESCE(
        jsonb_object_agg(scope_row.permission_key, scope_row.resource_ids),
        '{}'::jsonb
      )
        INTO v_scopes
        FROM (
          SELECT trp.permission_key,
                 jsonb_agg(DISTINCT elem ORDER BY elem) AS resource_ids
            FROM public.user_tenant_roles utr
            JOIN public.tenant_roles tr
              ON tr.id = utr.tenant_role_id
             AND tr.deleted_at IS NULL
            JOIN public.tenant_role_permissions trp
              ON trp.tenant_role_id = utr.tenant_role_id
           CROSS JOIN LATERAL jsonb_array_elements_text(
             COALESCE(trp.scope -> 'contract_ids', '[]'::jsonb)
           ) AS elem
           WHERE utr.user_id = v_user_id
             AND utr.organization_id = user_role.organization_id
             AND utr.revoked_at IS NULL
             AND utr.valid_from <= NOW()
             AND (utr.valid_until IS NULL OR utr.valid_until > NOW())
             AND trp.scope IS NOT NULL
           GROUP BY trp.permission_key
        ) AS scope_row;

      SELECT COALESCE(
        EXTRACT(EPOCH FROM MAX(tr.updated_at))::bigint,
        0
      )
        INTO v_perms_v
        FROM public.user_tenant_roles utr
        JOIN public.tenant_roles tr
          ON tr.id = utr.tenant_role_id
         AND tr.deleted_at IS NULL
       WHERE utr.user_id = v_user_id
         AND utr.organization_id = user_role.organization_id
         AND utr.revoked_at IS NULL
         AND utr.valid_from <= NOW()
         AND (utr.valid_until IS NULL OR utr.valid_until > NOW());
    END IF;

    claims := jsonb_set(claims, '{app_metadata, permissions}', v_perms);
    claims := jsonb_set(claims, '{app_metadata, perm_scopes}', v_scopes);
    claims := jsonb_set(claims, '{app_metadata, perms_v}', to_jsonb(v_perms_v));
  ELSE
    claims := jsonb_set(claims, '{app_metadata, super_admin}',   'false'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, org_id}',        'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, role}',          'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, contractor_id}', 'null'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, permissions}',   '[]'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, perm_scopes}',   '{}'::jsonb);
    claims := jsonb_set(claims, '{app_metadata, perms_v}',       '0'::jsonb);
  END IF;

  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook(jsonb) TO supabase_auth_admin;

-- ── 4. Retroactive Data Fix ──────────────────────────────────────────────────
-- Retroactively apply GoTrue ban to existing deactivated users
UPDATE auth.users
SET banned_until = 'infinity'
WHERE id IN (
  SELECT user_id 
  FROM public.user_roles 
  WHERE is_active = false
) AND (banned_until IS NULL OR banned_until != 'infinity');

RESET client_min_messages;
