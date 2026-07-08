-- =============================================================================
-- Migration: 20260920000001_bypass_dual_control_single_admin.sql
-- Description: Bypasses the four-eyes approval queue (role_change_requests)
-- when assigning or creating sensitive profiles in organizations that have
-- only 1 administrator.
-- Invariants: INV-2, INV-21, INV-22
-- =============================================================================

-- ── 1. Count Approvers Helper ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._rbac_count_approvers(p_org_id uuid)
RETURNS int
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT COUNT(DISTINCT u.user_id)::int
  FROM (
    -- Legacy / Superadmin assigned TENANT_ADMIN
    SELECT user_id
    FROM public.user_roles
    WHERE organization_id = p_org_id
      AND role = 'TENANT_ADMIN'
    
    UNION
    
    -- Users assigned the "Administrador" system profile
    SELECT utr.user_id
    FROM public.user_tenant_roles utr
    JOIN public.tenant_roles tr ON tr.id = utr.tenant_role_id
    WHERE utr.organization_id = p_org_id
      AND utr.revoked_at IS NULL
      AND (utr.valid_until IS NULL OR utr.valid_until > NOW())
      AND tr.is_system = true
      AND tr.name = 'Administrador'
  ) u;
$$;

GRANT EXECUTE ON FUNCTION public._rbac_count_approvers(uuid) TO authenticated, service_role;

-- ── 2. RPC: create_tenant_role ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_tenant_role(
  p_name        text,
  p_description text DEFAULT NULL,
  p_perm_grants jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id     uuid;
  v_caller_id  uuid;
  v_role_id    uuid;
  v_request_id uuid;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  v_org_id    := public._rbac_caller_org_id();
  v_caller_id := (auth.jwt() ->> 'sub')::uuid;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public._rbac_validate_grants(p_perm_grants);
  PERFORM public._rbac_assert_subset_grant(p_perm_grants);

  IF public._rbac_grants_touch_sensitive(p_perm_grants) AND public._rbac_count_approvers(v_org_id) > 1 THEN
    INSERT INTO public.role_change_requests (
      organization_id, request_type, payload, requested_by
    ) VALUES (
      v_org_id,
      'CREATE_ROLE',
      jsonb_build_object(
        'name', p_name,
        'description', p_description,
        'perm_grants', p_perm_grants
      ),
      v_caller_id
    )
    RETURNING id INTO v_request_id;

    PERFORM public._rbac_audit(
      'ROLE_CHANGE_REQUESTED',
      jsonb_build_object('request_id', v_request_id, 'request_type', 'CREATE_ROLE')
    );
    RETURN v_request_id;
  END IF;

  INSERT INTO public.tenant_roles (
    organization_id, name, description, is_system, created_by
  ) VALUES (
    v_org_id, p_name, p_description, false, v_caller_id
  )
  RETURNING id INTO v_role_id;

  PERFORM public._rbac_apply_grants(v_role_id, p_perm_grants);

  PERFORM public._rbac_audit(
    'ROLE_CREATED',
    jsonb_build_object('role_id', v_role_id, 'name', p_name)
  );

  RETURN v_role_id;
END;
$$;

-- ── 3. RPC: update_tenant_role_permissions ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_tenant_role_permissions(
  p_role_id     uuid,
  p_perm_grants jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id     uuid;
  v_caller_id  uuid;
  v_role       public.tenant_roles%ROWTYPE;
  v_request_id uuid;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  v_org_id    := public._rbac_caller_org_id();
  v_caller_id := (auth.jwt() ->> 'sub')::uuid;

  SELECT * INTO v_role
    FROM public.tenant_roles
   WHERE id = p_role_id
     AND organization_id = v_org_id
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_role.is_system THEN
    RAISE EXCEPTION 'System roles cannot be modified'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  PERFORM public._rbac_validate_grants(p_perm_grants);
  PERFORM public._rbac_assert_subset_grant(p_perm_grants);

  IF public._rbac_grants_touch_sensitive(p_perm_grants) AND public._rbac_count_approvers(v_org_id) > 1 THEN
    INSERT INTO public.role_change_requests (
      organization_id, request_type, payload, requested_by
    ) VALUES (
      v_org_id,
      'UPDATE_ROLE_PERMISSIONS',
      jsonb_build_object('role_id', p_role_id, 'perm_grants', p_perm_grants),
      v_caller_id
    )
    RETURNING id INTO v_request_id;

    PERFORM public._rbac_audit(
      'ROLE_CHANGE_REQUESTED',
      jsonb_build_object('request_id', v_request_id, 'request_type', 'UPDATE_ROLE_PERMISSIONS')
    );
    RETURN v_request_id;
  END IF;

  PERFORM public._rbac_apply_grants(p_role_id, p_perm_grants);

  PERFORM public._rbac_audit(
    'ROLE_PERMISSIONS_CHANGED',
    jsonb_build_object('role_id', p_role_id)
  );

  RETURN p_role_id;
END;
$$;

-- ── 4. RPC: assign_tenant_role ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assign_tenant_role(
  p_target_user uuid,
  p_role_id     uuid,
  p_valid_until timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id     uuid;
  v_caller_id  uuid;
  v_role       public.tenant_roles%ROWTYPE;
  v_request_id uuid;
  v_has_sensitive boolean;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  PERFORM public._rbac_assert_can_manage_target(p_target_user);
  PERFORM public._rbac_assert_can_grant_role(p_role_id);
  v_org_id    := public._rbac_caller_org_id();
  v_caller_id := (auth.jwt() ->> 'sub')::uuid;

  SELECT * INTO v_role
    FROM public.tenant_roles
   WHERE id = p_role_id
     AND organization_id = v_org_id
     AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles
     WHERE user_id = p_target_user
       AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS (
    SELECT 1
      FROM public.tenant_role_permissions trp
      JOIN public.tenant_permissions tp ON tp.key = trp.permission_key
     WHERE trp.tenant_role_id = p_role_id
       AND tp.is_sensitive
  ) INTO v_has_sensitive;

  IF v_has_sensitive AND public._rbac_count_approvers(v_org_id) > 1 THEN
    INSERT INTO public.role_change_requests (
      organization_id, request_type, payload, requested_by
    ) VALUES (
      v_org_id,
      'GRANT_ROLE',
      jsonb_build_object(
        'target_user', p_target_user,
        'role_id', p_role_id,
        'valid_until', p_valid_until
      ),
      v_caller_id
    )
    RETURNING id INTO v_request_id;

    PERFORM public._rbac_audit(
      'ROLE_CHANGE_REQUESTED',
      jsonb_build_object('request_id', v_request_id, 'request_type', 'GRANT_ROLE')
    );
    RETURN v_request_id;
  END IF;

  INSERT INTO public.user_tenant_roles (
    user_id, tenant_role_id, organization_id, valid_until, granted_by, revoked_at
  ) VALUES (
    p_target_user, p_role_id, v_org_id, p_valid_until, v_caller_id, NULL
  )
  ON CONFLICT (user_id, tenant_role_id) DO UPDATE
    SET valid_until = EXCLUDED.valid_until,
        granted_by  = EXCLUDED.granted_by,
        revoked_at  = NULL,
        valid_from  = NOW();

  UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = p_role_id;
  PERFORM public._rbac_sync_coarse_role_admin(p_target_user, v_org_id);

  PERFORM public._rbac_audit(
    'ROLE_ASSIGNED',
    jsonb_build_object('target_user', p_target_user, 'role_id', p_role_id)
  );

  RETURN p_role_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.assign_tenant_role(uuid, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_tenant_role(uuid, uuid, timestamptz) TO service_role;
