-- pr_scanner: ignore-regression
-- =============================================================================
-- Migration: 20260912000001 — Tenant RBAC hardening (Pilar 1 post-audit F1-F4)
--
-- Tier-1 audit of Pilar 1 approved with four mandatory fixes:
--   F1  service_role lacked EXECUTE on the 6 mutation RPCs + revoke_user_sessions
--       (REVOKE … FROM PUBLIC without a service_role re-grant — the same trap
--        that once cascaded 85 E2E failures via the MFA RPCs). Re-grant here.
--   F2  approve_role_change did not re-verify the subset guard against the
--       APPROVER. A requester could enqueue a grant, lose the permission, and a
--       second admin holding only 'roles:manage' would still apply it above
--       their own ceiling. Re-inject _rbac_assert_subset_grant on approval.
--   F3  Lazy 72h expiry lived only in approve_role_change; reject_role_change
--       stamped a misleading 'REJECTED' on an already-expired request. Mirror
--       the expiry block into reject.
--   F4  Live-check covered only sla:approve; a revoked 'roles:manage' stayed
--       effective until the 300s TTL inside the RBAC RPCs themselves. Converge
--       the success paths of _rbac_assert_roles_manage through one live-check.
--
-- Documented non-gaps (deliberate, not defects):
--   • Helpers live in public.* not auth.* — Supabase blocks CREATE in the auth
--     schema; public SECURITY DEFINER with REVOKE-from-clients is the pattern.
--   • Org claim split — RLS reads the top-level 'organization_id' claim, the
--     RPCs read 'app_metadata.org_id'; both are populated by the JWT hook and
--     the split is the dominant repo convention.
--   • No last-admin protection — TENANT_ADMIN is coarse on the trust root
--     (user_roles) and always receives '*', so a tenant can never lock itself
--     out of role management by editing custom tenant_roles.
--   • financial:export live-check deferred — no export RPC exists yet to inject
--     the check into.
--
-- Invariants: INV-1, INV-2, INV-3, INV-10, INV-21, INV-22, INV-26.
-- Council sign-off: QA/Security | Lead Reviewer
-- pr_scanner: ignore-regression
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- ── F1: service_role EXECUTE on the mutation RPCs + session revoker ───────────
GRANT EXECUTE ON FUNCTION public.create_tenant_role(text, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_tenant_role_permissions(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.assign_tenant_role(uuid, uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_tenant_role(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.approve_role_change(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.reject_role_change(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_user_sessions(uuid) TO service_role;

-- ── F4: converge success paths of the roles:manage guard through live-check ───
-- Semantics handled by _rbac_live_check_permission:
--   • has_permission('*')          → bypass, no DB hit
--   • claim 'roles:manage' absent  → bypass (coarse token)
--   • claim present                → DB truth (revoked row ⇒ 42501)
CREATE OR REPLACE FUNCTION public._rbac_assert_roles_manage()
RETURNS void
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
  IF public.has_permission('roles:manage') OR public.has_permission('*')
     OR (auth.jwt() -> 'app_metadata' ->> 'role') = 'TENANT_ADMIN' THEN
    PERFORM public._rbac_live_check_permission('roles:manage');
    RETURN;
  END IF;
  RAISE EXCEPTION 'Unauthorized'
    USING ERRCODE = 'insufficient_privilege';
END;
$$;

-- ── F2: re-verify approver's subset ceiling on approval ──────────────────────
-- Body verbatim from 20260909000004 (the only definition) with the subset
-- guard injected per request type so the approver — not the requester — is the
-- authority whose held permissions bound the applied grant.
CREATE OR REPLACE FUNCTION public.approve_role_change(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id       uuid;
  v_caller_id    uuid;
  v_req          public.role_change_requests%ROWTYPE;
  v_role_id      uuid;
  v_payload      jsonb;
  v_role_grants  jsonb;
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
      IF NOT EXISTS (
        SELECT 1 FROM public.tenant_roles
         WHERE id = v_role_id
           AND organization_id = v_org_id
           AND deleted_at IS NULL
      ) THEN
        RAISE EXCEPTION 'Not found.'
          USING ERRCODE = 'insufficient_privilege';
      END IF;
      -- F2: the approver must hold every permission the granted role carries,
      -- otherwise two sub-admins could route a financial role via approval.
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

-- ── F3: expire stale requests on reject instead of stamping REJECTED ─────────
-- Body verbatim from 20260909000004 with the 72h expiry block mirrored from
-- approve_role_change (inserted after the pending check).
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

  IF v_req.created_at < NOW() - INTERVAL '72 hours' THEN
    UPDATE public.role_change_requests
       SET status = 'EXPIRED'
     WHERE id = p_request_id;
    RAISE EXCEPTION 'Request has expired'
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
