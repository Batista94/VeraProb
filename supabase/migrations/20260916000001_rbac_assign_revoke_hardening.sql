-- =============================================================================
-- Migration: 20260916000001 — RBAC assign/revoke hierarchy hardening (Case 2)
--
-- Closes a live privilege-escalation gap: assign_tenant_role / revoke_tenant_role
-- previously enforced only _rbac_assert_roles_manage(), so a Validador (holding
-- 'roles:manage' but a strict permission subset) could grant/revoke Administrador
-- and manage targets above their own ceiling.
--
-- Adds three internal guards, invoked inside the existing org-scoped SECURITY
-- DEFINER RPCs (no RLS/grant surface change — INV-2, INV-22 preserved):
--   _rbac_assert_can_grant_role   — caller must hold every key of the role.
--   _rbac_assert_can_manage_target — caller must hold every key the target holds.
--   _rbac_sync_coarse_role_admin  — holding the system 'Administrador' tenant role
--                                   ⟺ coarse user_roles.role='TENANT_ADMIN' (JWT '*'),
--                                   with a last-admin demotion guard.
--
-- assign/revoke/approve bodies are CREATE OR REPLACE-d from their LATEST prior
-- definitions (revoke: 20260910000003 auto-kill sessions; approve: 20260912000001
-- F2 subset guards) with the guards + coarse-sync injected — no fork dropped.
--
-- Invariants: INV-1, INV-2, INV-3, INV-10, INV-21, INV-22, INV-26.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── Helpers ───────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._rbac_assert_can_grant_role(p_role_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_has_all boolean;
  v_perm_key text;
BEGIN
  v_has_all := COALESCE((auth.jwt() -> 'app_metadata' -> 'permissions') ? '*', false);
  IF v_has_all THEN
    RETURN;
  END IF;

  FOR v_perm_key IN 
    SELECT permission_key 
      FROM public.tenant_role_permissions 
     WHERE tenant_role_id = p_role_id 
  LOOP
    IF NOT public.has_permission(v_perm_key) THEN
      RAISE EXCEPTION 'insufficient_privilege to grant/revoke role'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public._rbac_assert_can_manage_target(p_target_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_has_all boolean;
  v_target_perm text;
  v_org_id uuid;
BEGIN
  v_has_all := COALESCE((auth.jwt() -> 'app_metadata' -> 'permissions') ? '*', false);
  IF v_has_all THEN
    RETURN;
  END IF;

  v_org_id := public._rbac_caller_org_id();

  FOR v_target_perm IN
    SELECT DISTINCT trp.permission_key
      FROM public.user_tenant_roles utr
      JOIN public.tenant_role_permissions trp ON trp.tenant_role_id = utr.tenant_role_id
     WHERE utr.user_id = p_target_user
       AND utr.organization_id = v_org_id
       AND utr.revoked_at IS NULL
       AND (utr.valid_until IS NULL OR utr.valid_until > NOW())
  LOOP
    IF NOT public.has_permission(v_target_perm) THEN
      RAISE EXCEPTION 'insufficient_privilege to manage target user'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public._rbac_sync_coarse_role_admin(p_user uuid, p_org uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_holds_admin boolean;
  v_current_coarse text;
  v_admin_count int;
BEGIN
  SELECT EXISTS (
    SELECT 1 
      FROM public.user_tenant_roles utr
      JOIN public.tenant_roles tr ON tr.id = utr.tenant_role_id
     WHERE utr.user_id = p_user
       AND utr.organization_id = p_org
       AND utr.revoked_at IS NULL
       AND (utr.valid_until IS NULL OR utr.valid_until > NOW())
       AND tr.is_system = true
       AND tr.name = 'Administrador'
  ) INTO v_holds_admin;

  SELECT role INTO v_current_coarse 
    FROM public.user_roles 
   WHERE user_id = p_user 
     AND organization_id = p_org;
     
  IF v_holds_admin THEN
    IF v_current_coarse <> 'TENANT_ADMIN' THEN
      UPDATE public.user_roles 
         SET role = 'TENANT_ADMIN' 
       WHERE user_id = p_user 
         AND organization_id = p_org;
    END IF;
  ELSE
    IF v_current_coarse = 'TENANT_ADMIN' THEN
      SELECT COUNT(*) INTO v_admin_count 
        FROM public.user_roles
       WHERE organization_id = p_org 
         AND role = 'TENANT_ADMIN' 
         AND is_active = true;
         
      IF v_admin_count <= 1 THEN
        RAISE EXCEPTION 'Cannot demote the last administrator' 
          USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
      END IF;

      UPDATE public.user_roles 
         SET role = 'OPERATOR' 
       WHERE user_id = p_user 
         AND organization_id = p_org;
    END IF;
  END IF;
END;
$$;

-- ── RPC: assign_tenant_role ───────────────────────────────────────────────────
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

  IF v_has_sensitive THEN
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

-- ── RPC: revoke_tenant_role ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_tenant_role(
  p_target_user uuid,
  p_role_id     uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
  v_org_id uuid;
  v_has_sensitive boolean;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  PERFORM public._rbac_assert_can_manage_target(p_target_user);
  PERFORM public._rbac_assert_can_grant_role(p_role_id);
  v_org_id := public._rbac_caller_org_id();

  UPDATE public.user_tenant_roles
     SET revoked_at = NOW()
   WHERE user_id = p_target_user
     AND tenant_role_id = p_role_id
     AND organization_id = v_org_id
     AND revoked_at IS NULL;

  IF NOT FOUND THEN
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

  IF v_has_sensitive THEN
    PERFORM public.revoke_user_sessions(p_target_user);
  END IF;

  UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = p_role_id;
  PERFORM public._rbac_sync_coarse_role_admin(p_target_user, v_org_id);

  PERFORM public._rbac_audit(
    'ROLE_REVOKED',
    jsonb_build_object('target_user', p_target_user, 'role_id', p_role_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO service_role;

-- ── RPC: approve_role_change (four-eyes) ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_role_change(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id     uuid;
  v_caller_id  uuid;
  v_req        public.role_change_requests%ROWTYPE;
  v_role_id    uuid;
  v_payload    jsonb;
  v_target_user uuid;
  v_role_grants jsonb;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
  v_org_id    := public._rbac_caller_org_id();
  v_caller_id := (auth.jwt() ->> 'sub')::uuid;

  SELECT * INTO v_req
    FROM public.role_change_requests
   WHERE id = p_request_id
     AND organization_id = v_org_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_req.status <> 'PENDING' THEN
    RAISE EXCEPTION 'Request is not pending'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  IF v_req.created_at < NOW() - INTERVAL '72 hours' THEN
    UPDATE public.role_change_requests
       SET status = 'EXPIRED'
     WHERE id = p_request_id;
    RAISE EXCEPTION 'Request has expired'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  IF v_req.requested_by = v_caller_id THEN
    RAISE EXCEPTION 'Self-approval is not permitted'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  v_payload := v_req.payload;

  CASE v_req.request_type
    WHEN 'CREATE_ROLE' THEN
      PERFORM public._rbac_validate_grants(v_payload -> 'perm_grants');
      -- F2: the approver cannot apply a grant above their own ceiling.
      PERFORM public._rbac_assert_subset_grant(v_payload -> 'perm_grants');
      INSERT INTO public.tenant_roles (
        organization_id, name, description, is_system, created_by
      ) VALUES (
        v_org_id,
        v_payload ->> 'name',
        v_payload ->> 'description',
        false,
        v_req.requested_by
      )
      RETURNING id INTO v_role_id;
      PERFORM public._rbac_apply_grants(v_role_id, v_payload -> 'perm_grants');

    WHEN 'UPDATE_ROLE_PERMISSIONS' THEN
      v_role_id := (v_payload ->> 'role_id')::uuid;
      IF NOT EXISTS (
        SELECT 1 FROM public.tenant_roles
         WHERE id = v_role_id
           AND organization_id = v_org_id
           AND deleted_at IS NULL
           AND NOT is_system
      ) THEN
        RAISE EXCEPTION 'Not found.'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
      PERFORM public._rbac_validate_grants(v_payload -> 'perm_grants');
      -- F2: bound the applied grant by the approver's held permissions.
      PERFORM public._rbac_assert_subset_grant(v_payload -> 'perm_grants');
      PERFORM public._rbac_apply_grants(v_role_id, v_payload -> 'perm_grants');

    WHEN 'GRANT_ROLE' THEN
      v_role_id := (v_payload ->> 'role_id')::uuid;
      v_target_user := (v_payload ->> 'target_user')::uuid;
      IF NOT EXISTS (
        SELECT 1 FROM public.tenant_roles
         WHERE id = v_role_id
           AND organization_id = v_org_id
           AND deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'Not found.'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- F2: the approver must hold every permission the granted role carries.
      SELECT jsonb_agg(jsonb_build_object('key', permission_key))
        INTO v_role_grants
        FROM public.tenant_role_permissions
       WHERE tenant_role_id = v_role_id;
      IF v_role_grants IS NOT NULL THEN
        PERFORM public._rbac_assert_subset_grant(v_role_grants);
      END IF;
      INSERT INTO public.user_tenant_roles (
        user_id, tenant_role_id, organization_id, valid_until, granted_by, revoked_at
      ) VALUES (
        v_target_user,
        v_role_id,
        v_org_id,
        (v_payload ->> 'valid_until')::timestamptz,
        v_req.requested_by,
        NULL
      )
      ON CONFLICT (user_id, tenant_role_id) DO UPDATE
        SET valid_until = EXCLUDED.valid_until,
            granted_by  = EXCLUDED.granted_by,
            revoked_at  = NULL,
            valid_from  = NOW();
      UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = v_role_id;
      PERFORM public._rbac_sync_coarse_role_admin(v_target_user, v_org_id);

    ELSE
      RAISE EXCEPTION 'Unknown request type'
        USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END CASE;

  UPDATE public.role_change_requests
     SET status = 'APPROVED',
         decided_by = v_caller_id,
         decided_at = NOW()
   WHERE id = p_request_id;

  PERFORM public._rbac_audit(
    'ROLE_CHANGE_APPROVED',
    jsonb_build_object('request_id', p_request_id, 'decided_by', v_caller_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_role_change(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_role_change(uuid) TO service_role;

-- ── Internal helpers: not callable by API clients (INV-2, INV-22) ─────────────
REVOKE ALL ON FUNCTION public._rbac_assert_can_grant_role(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_assert_can_manage_target(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_sync_coarse_role_admin(uuid, uuid) FROM PUBLIC, anon, authenticated;

RESET client_min_messages;
