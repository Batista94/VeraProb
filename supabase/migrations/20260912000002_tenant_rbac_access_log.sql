-- =============================================================================
-- Migration: 20260912000002 — RBAC route-guard audit sink (Pilar 3)
--
-- log_access_denied(route, required_perm): lightweight fire-and-forget sink for
-- the GoRouter redirect guard. When a tenant user hits a route whose permission
-- they lack, the router silently ejects them to the admin hub (anti-oracle,
-- INV-26) and calls this RPC to leave an immutable 'ACCESS_DENIED' trail
-- (INV-21). The router is UX/defense-in-depth only — RLS/RPCs remain the truth.
--
-- Why SECURITY DEFINER: org is derived server-side from the JWT
-- (app_metadata.org_id, the RPC claim convention) via _rbac_caller_org_id,
-- which is REVOKEd from client roles. The actor id is read from the verified
-- 'sub' claim so the route/perm the client passes cannot be attributed to
-- another user. Unauthenticated callers are a no-op (nothing to attribute).
--
-- Invariants: INV-1, INV-2, INV-10, INV-21, INV-26.
-- Council sign-off: QA/Security | Lead Reviewer
-- =============================================================================

SET client_min_messages TO 'WARNING';

CREATE OR REPLACE FUNCTION public.log_access_denied(
  p_route          text,
  p_required_perm  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id    uuid := public._rbac_caller_org_id();
  v_actor_id  uuid := NULLIF(auth.jwt() ->> 'sub', '')::uuid;
BEGIN
  IF v_actor_id IS NULL THEN
    RETURN;  -- no verified subject → nothing to attribute (no-op)
  END IF;

  INSERT INTO public.system_audit_log (
    event_type, severity, organization_id, payload
  ) VALUES (
    'ACCESS_DENIED',
    'warning',
    v_org_id,
    jsonb_build_object(
      'route',    p_route,
      'required', p_required_perm,
      'org',      v_org_id,
      'actor_id', v_actor_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.log_access_denied(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_access_denied(text, text)
  TO authenticated, service_role;
