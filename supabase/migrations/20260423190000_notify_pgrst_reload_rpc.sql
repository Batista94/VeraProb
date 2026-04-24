-- Migration: PostgREST schema cache reload RPC
--
-- Exposes pg_notify('pgrst', 'reload schema') as a callable RPC so that
-- integration tests can trigger a schema cache reload after db reset without
-- requiring direct DB access.
--
-- SECURITY: SECURITY DEFINER runs as postgres (superuser), which is the only
-- role allowed to call pg_notify on the 'pgrst' channel. EXECUTE is revoked
-- from PUBLIC and granted only to service_role — it cannot be called by
-- authenticated tenant users.

CREATE OR REPLACE FUNCTION public.notify_pgrst_reload()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pg_notify('pgrst', 'reload schema');
$$;

REVOKE ALL ON FUNCTION public.notify_pgrst_reload() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_pgrst_reload() TO service_role;
