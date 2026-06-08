--
-- Suppress DROP TRIGGER/POLICY IF EXISTS NOTICEs.
SET client_min_messages TO 'WARNING';

-- =============================================================================
-- Migration: 20260606000001 — Grant authenticated access to idempotency_keys
--
-- PURPOSE:
--   Fixes CI Block #13 (INV-DATA-API-GRANT): migration 20260413000002
--   created public.idempotency_keys and its RPC functions but omitted
--   GRANT statements. PostgREST rejects all client requests with 403
--   when table-level and function-level grants are absent.
--
-- CONSTRAINTS:
--   - DELETE intentionally NOT granted to authenticated: trigger
--     trg_idempotency_no_delete_processing (INV-33) blocks deletion of
--     'processing' keys. Cleanup is SECURITY DEFINER (service_role only).
--   - prevent_idempotency_key_mutation and prevent_idempotency_processing_delete
--     are trigger functions — not directly callable, no EXECUTE grant needed.
-- =============================================================================

-- ── 1. Table grants ──────────────────────────────────────────────────────────

REVOKE ALL ON TABLE public.idempotency_keys FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.idempotency_keys TO authenticated;
GRANT ALL ON TABLE public.idempotency_keys TO service_role;

-- ── 2. RPC function grants (dynamic — resolves canonical signature from pg_proc)
--
-- Static GRANT EXECUTE ON FUNCTION f(TYPE, ...) fails when PostgreSQL's internal
-- type registration differs from the alias used at CREATE time (e.g., INT vs INTEGER).
-- Using pg_get_function_identity_arguments(oid) resolves the exact canonical
-- signature and generates correct GRANT statements regardless of alias.

DO $$
DECLARE
  r          RECORD;
  v_fn       TEXT;
  v_client   TEXT[] := ARRAY[
    'try_acquire_idempotency_key',
    'complete_idempotency_key',
    'fail_idempotency_key'
  ];
BEGIN
  -- Grant client-facing functions to both roles.
  FOR r IN
    SELECT p.proname,
           pg_catalog.pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_catalog.pg_proc     p
      JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public'
       AND p.proname = ANY(v_client)
  LOOP
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated',
      r.proname, r.args
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.%I(%s) TO service_role',
      r.proname, r.args
    );
  END LOOP;

  -- Maintenance cleanup: service_role only (SECURITY DEFINER — not for clients).
  FOR r IN
    SELECT p.proname,
           pg_catalog.pg_get_function_identity_arguments(p.oid) AS args
      FROM pg_catalog.pg_proc     p
      JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public'
       AND p.proname = 'cleanup_expired_idempotency'
  LOOP
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.%I(%s) TO service_role',
      r.proname, r.args
    );
  END LOOP;

  -- Hard check: all 3 client functions must exist.
  -- If any is missing, migration 20260413000002 did not fully apply.
  FOREACH v_fn IN ARRAY v_client LOOP
    IF NOT EXISTS (
      SELECT 1
        FROM pg_catalog.pg_proc     p
        JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
       WHERE n.nspname = 'public'
         AND p.proname = v_fn
    ) THEN
      RAISE EXCEPTION
        'public.% not found. Migration 20260413000002 may not have applied fully. '
        'Run supabase db reset to restore clean state.',
        v_fn;
    END IF;
  END LOOP;
END
$$;

-- ── 3. Verification ──────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
     WHERE grantee        = 'authenticated'
       AND table_schema   = 'public'
       AND table_name     = 'idempotency_keys'
       AND privilege_type = 'INSERT'
  ) THEN
    RAISE EXCEPTION 'GRANT INSERT on idempotency_keys for authenticated was not applied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.role_table_grants
     WHERE grantee        = 'authenticated'
       AND table_schema   = 'public'
       AND table_name     = 'idempotency_keys'
       AND privilege_type = 'UPDATE'
  ) THEN
    RAISE EXCEPTION 'GRANT UPDATE on idempotency_keys for authenticated was not applied';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges
     WHERE grantee        = 'authenticated'
       AND routine_schema = 'public'
       AND routine_name   = 'try_acquire_idempotency_key'
       AND privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'GRANT EXECUTE on try_acquire_idempotency_key for authenticated was not applied';
  END IF;

  RAISE NOTICE '✅ idempotency_keys grants applied for authenticated + service_role (INV-DATA-API-GRANT)';
END
$$;
