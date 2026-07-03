-- =============================================================================
-- Migration: 20260909000004 — Tenant RBAC mutation RPCs (Pilar 1.4)
--
-- SECURITY DEFINER write path with subset guard, org scope, four-eyes for
-- sensitive permissions, and structured audit events.
-- Invariants: INV-1, INV-2, INV-3, INV-10, INV-21, INV-22, INV-26.
-- =============================================================================

-- ── Internal: caller org from JWT ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._rbac_caller_org_id()
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = public, auth
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid;
$$;

-- ── Internal: assert caller may manage roles ──────────────────────────────────
CREATE OR REPLACE FUNCTION public._rbac_assert_roles_manage()
RETURNS void
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
  IF public.has_permission('roles:manage') OR public.has_permission('*') THEN
    RETURN;
  END IF;
  IF (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN' THEN
    RETURN;
  END IF;
  RAISE EXCEPTION 'Unauthorized'
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

-- ── Internal: extract permission keys from grants array ───────────────────────
CREATE OR REPLACE FUNCTION public._rbac_grant_keys(p_grants jsonb)
RETURNS SETOF text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT elem ->> 'key'
    FROM jsonb_array_elements(
      CASE
        WHEN jsonb_typeof(p_grants) = 'array' THEN p_grants
        ELSE '[]'::jsonb
      END
    ) AS elem
   WHERE elem ? 'key';
$$;

-- ── Internal: subset guard — caller cannot grant unheld permissions ───────────
CREATE OR REPLACE FUNCTION public._rbac_assert_subset_grant(p_grants jsonb)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
DECLARE
  v_key text;
BEGIN
  IF public.has_permission('*') THEN
    RETURN;
  END IF;

  FOR v_key IN SELECT public._rbac_grant_keys(p_grants)
  LOOP
    IF NOT public.has_permission(v_key) THEN
      RAISE EXCEPTION 'PrivilegeEscalation: cannot grant unheld permission'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;
END;
$$;

-- ── Internal: validate grant keys + scope shape against dictionary ──────────
CREATE OR REPLACE FUNCTION public._rbac_validate_grants(p_grants jsonb)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_elem   jsonb;
  v_key    text;
  v_scope  jsonb;
  v_meta   public.tenant_permissions%ROWTYPE;
BEGIN
  IF jsonb_typeof(p_grants) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Invalid permission grants payload'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  FOR v_elem IN SELECT value FROM jsonb_array_elements(p_grants)
  LOOP
    v_key := v_elem ->> 'key';
    IF v_key IS NULL OR v_key = '' THEN
      RAISE EXCEPTION 'Permission key is required'
        USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
    END IF;

    SELECT * INTO v_meta FROM public.tenant_permissions WHERE key = v_key;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Unknown permission key: %', v_key
        USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
    END IF;

    v_scope := v_elem -> 'scope';
    IF v_scope IS NOT NULL AND NOT v_meta.is_scopable THEN
      RAISE EXCEPTION 'Permission % does not accept resource scope', v_key
        USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
    END IF;

    IF v_scope IS NOT NULL
       AND v_scope ? 'contract_ids'
       AND jsonb_array_length(v_scope -> 'contract_ids') > 32 THEN
      RAISE EXCEPTION 'Scope exceeds maximum of 32 resource IDs'
        USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
    END IF;
  END LOOP;
END;
$$;

-- ── Internal: detect sensitive permissions in grant set ─────────────────────
CREATE OR REPLACE FUNCTION public._rbac_grants_touch_sensitive(p_grants jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public._rbac_grant_keys(p_grants) AS k
      JOIN public.tenant_permissions tp ON tp.key = k
     WHERE tp.is_sensitive
  );
$$;

-- ── Internal: append role audit event ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._rbac_audit(
  p_event_type text,
  p_payload    jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source, organization_id, occurred_at
  ) VALUES (
    p_event_type,
    'info',
    p_payload,
    'tenant_rbac_rpc',
    public._rbac_caller_org_id(),
    NOW()
  );
END;
$$;

-- ── Internal: apply permission grants to a role ─────────────────────────────
CREATE OR REPLACE FUNCTION public._rbac_apply_grants(
  p_role_id uuid,
  p_grants  jsonb
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_elem jsonb;
  v_key  text;
BEGIN
  DELETE FROM public.tenant_role_permissions
   WHERE tenant_role_id = p_role_id;

  FOR v_elem IN SELECT value FROM jsonb_array_elements(p_grants)
  LOOP
    v_key := v_elem ->> 'key';
    INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_key, scope)
    VALUES (p_role_id, v_key, v_elem -> 'scope');
  END LOOP;

  UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = p_role_id;
END;
$$;

-- ── RPC: create_tenant_role ───────────────────────────────────────────────────
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

  IF public._rbac_grants_touch_sensitive(p_perm_grants) THEN
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

-- ── RPC: update_tenant_role_permissions ─────────────────────────────────────
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

  IF public._rbac_grants_touch_sensitive(p_perm_grants) THEN
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

  PERFORM public._rbac_audit(
    'ROLE_ASSIGNED',
    jsonb_build_object('target_user', p_target_user, 'role_id', p_role_id)
  );

  RETURN p_role_id;
END;
$$;

-- ── RPC: revoke_tenant_role ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_tenant_role(
  p_target_user uuid,
  p_role_id     uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  PERFORM public._rbac_assert_roles_manage();
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

  UPDATE public.tenant_roles SET updated_at = NOW() WHERE id = p_role_id;

  PERFORM public._rbac_audit(
    'ROLE_REVOKED',
    jsonb_build_object('target_user', p_target_user, 'role_id', p_role_id)
  );
END;
$$;

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
      PERFORM public._rbac_apply_grants(v_role_id, v_payload -> 'perm_grants');

    WHEN 'GRANT_ROLE' THEN
      v_role_id := (v_payload ->> 'role_id')::uuid;
      IF NOT EXISTS (
        SELECT 1 FROM public.tenant_roles
         WHERE id = v_role_id
           AND organization_id = v_org_id
           AND deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'Not found.'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
      INSERT INTO public.user_tenant_roles (
        user_id, tenant_role_id, organization_id, valid_until, granted_by, revoked_at
      ) VALUES (
        (v_payload ->> 'target_user')::uuid,
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

-- ── RPC: reject_role_change (four-eyes) ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_role_change(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id    uuid;
  v_caller_id uuid;
  v_req       public.role_change_requests%ROWTYPE;
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

  IF v_req.requested_by = v_caller_id THEN
    RAISE EXCEPTION 'Self-rejection by requester is not permitted'
      USING ERRCODE = 'P0001', DETAIL = 'IntegrityException';
  END IF;

  UPDATE public.role_change_requests
     SET status = 'REJECTED',
         decided_by = v_caller_id,
         decided_at = NOW()
   WHERE id = p_request_id;

  PERFORM public._rbac_audit(
    'ROLE_CHANGE_REJECTED',
    jsonb_build_object('request_id', p_request_id, 'decided_by', v_caller_id)
  );
END;
$$;

-- ── Grants: mutation RPCs only for authenticated ─────────────────────────────
REVOKE ALL ON FUNCTION public.create_tenant_role(text, text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_tenant_role_permissions(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.assign_tenant_role(uuid, uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_tenant_role(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.approve_role_change(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reject_role_change(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_tenant_role(text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_tenant_role_permissions(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_tenant_role(uuid, uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_role_change(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_role_change(uuid) TO authenticated;

-- Internal helpers: definer-only (not exposed to clients).
REVOKE ALL ON FUNCTION public._rbac_caller_org_id() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_assert_roles_manage() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_grant_keys(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_assert_subset_grant(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_validate_grants(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_grants_touch_sensitive(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_apply_grants(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._rbac_audit(text, jsonb) FROM PUBLIC, anon, authenticated;
