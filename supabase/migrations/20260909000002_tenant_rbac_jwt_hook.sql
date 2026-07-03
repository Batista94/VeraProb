-- =============================================================================
-- Migration: 20260909000002 — JWT hook: aggregate tenant RBAC into app_metadata
-- (Pilar 1.2)
--
-- Extends custom_access_token_hook to inject:
--   app_metadata.permissions[]  — union of active custom roles (or ["*"] for admin)
--   app_metadata.perm_scopes{}  — ABAC-lite resource allowlists
--   app_metadata.perms_v        — max(tenant_roles.updated_at) epoch for refresh
-- Invariants: INV-1, INV-2, INV-6.
-- =============================================================================

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
   WHERE ur.user_id = v_user_id;

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
