-- =============================================================================
-- Migration: 20260910000002 — revoke_user_sessions RPC (Pilar 1.5 Kill-Session)
--
-- Exposes revoke_user_sessions(target_user uuid) to authenticated users with
-- roles:manage permission. The RPC verifies org scope then calls the
-- revoke-user-sessions Edge Function via pg_net (fire-and-forget) to
-- invalidate all refresh tokens via auth.admin.signOut(userId, 'global').
-- Audits SESSIONS_REVOKED to system_audit_log for forensic completeness.
--
-- Pre-requisites (set once via Supabase Dashboard → Database → Parameters):
--   ALTER DATABASE postgres SET "app.supabase_url" = 'https://<ref>.supabase.co';
--   ALTER DATABASE postgres SET "app.supabase_service_role_key" = '<service_key>';
--
-- Invariants: INV-1, INV-10, INV-21, INV-22, INV-26.
-- =============================================================================

SET client_min_messages TO 'WARNING';

-- pg_net: standard Supabase-managed extension for async HTTP from plpgsql.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── RPC: revoke_user_sessions ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_user_sessions(p_target_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
DECLARE
  v_org_id    uuid;
  v_caller_id uuid;
BEGIN
  -- ── 1. Caller must have roles:manage (or wildcard) ──────────────────────────
  PERFORM public._rbac_assert_roles_manage();

  v_org_id    := public._rbac_caller_org_id();
  v_caller_id := (auth.jwt() ->> 'sub')::uuid;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── 2. Target must belong to the same org (INV-22 / INV-26 not-found parity)
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles
     WHERE user_id = p_target_user
       AND organization_id = v_org_id
  ) THEN
    RAISE EXCEPTION 'Not found.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── 3. Audit before HTTP call (append-only — INV-3, INV-21) ──────────────────
  INSERT INTO public.system_audit_log (
    event_type, severity, payload, source, organization_id, occurred_at
  ) VALUES (
    'SESSIONS_REVOKED',
    'info',
    jsonb_build_object(
      'target_user', p_target_user,
      'requested_by', v_caller_id
    ),
    'tenant_rbac_rpc',
    v_org_id,
    NOW()
  );

  -- ── 4. Fire-and-forget: call Edge Function via pg_net (async HTTP) ───────────
  -- The Edge Function validates the service_role Bearer token and calls
  -- auth.admin.signOut(userId, 'global') to delete all refresh tokens.
  -- pg_net returns immediately; the HTTP call completes within seconds.
  -- current_setting(..., true) returns NULL when the GUC is not configured
  -- (test env / missing ALTER DATABASE SET), silently skipping the call.
  IF current_setting('app.supabase_url', true) IS NOT NULL THEN
    PERFORM net.http_post(
      url     := current_setting('app.supabase_url', true)
                 || '/functions/v1/revoke-user-sessions',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || coalesce(
          current_setting('app.supabase_service_role_key', true), ''
        )
      ),
      body    := jsonb_build_object('user_id', p_target_user)::text
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_user_sessions(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_user_sessions(uuid) TO authenticated;

RESET client_min_messages;
