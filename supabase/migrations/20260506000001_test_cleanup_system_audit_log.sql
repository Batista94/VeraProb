-- =============================================================================
-- Test cleanup helper for system_audit_log (CT29 — F1/F3 integration suites).
--
-- Background: system_audit_log has `INSTEAD NOTHING` rules on UPDATE/DELETE
-- (INV-3 append-only). Even service_role cannot DELETE through PostgREST. The
-- only safe teardown path for integration tests is a SECURITY DEFINER RPC that
-- runs as the function owner (postgres) and bypasses both the rules and any
-- future RLS policies on the table.
--
-- Mirrors the pattern of test_cleanup_forensic_data (Telegram cleanup).
--
-- INV-3: append-only is the production rule. This RPC is a TEST-ONLY backdoor
-- and is never called from application code. EXECUTE is granted to service_role
-- exclusively; PUBLIC is revoked.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.test_cleanup_system_audit_log(p_org_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Disable the INSTEAD NOTHING rule by issuing the DELETE as the function
  -- owner (postgres). DROP+CREATE the rules around the DELETE in a single
  -- transaction so concurrent INSERTs are still blocked from mutation paths.
  ALTER TABLE public.system_audit_log DISABLE RULE system_audit_log_no_delete;

  IF array_length(p_org_ids, 1) IS NULL THEN
    -- Empty array → only system-level rows (organization_id IS NULL).
    DELETE FROM public.system_audit_log
     WHERE organization_id IS NULL;
  ELSE
    DELETE FROM public.system_audit_log
     WHERE organization_id = ANY(p_org_ids)
        OR organization_id IS NULL;
  END IF;

  ALTER TABLE public.system_audit_log ENABLE RULE system_audit_log_no_delete;
END;
$$;

REVOKE ALL ON FUNCTION public.test_cleanup_system_audit_log(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.test_cleanup_system_audit_log(UUID[]) TO service_role;

COMMENT ON FUNCTION public.test_cleanup_system_audit_log(UUID[]) IS
  'TEST ONLY — bypasses INSTEAD NOTHING DELETE rule on system_audit_log. '
  'Granted only to service_role for integration test teardown (INV-3).';
