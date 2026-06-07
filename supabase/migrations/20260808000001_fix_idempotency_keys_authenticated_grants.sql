-- =============================================================================
-- Fix: idempotency_keys authenticated grants (UAT CT04 regression)
--
-- PURPOSE:
--   Migration 20260717000005 incorrectly classified idempotency_keys as an
--   "internal server table" and issued REVOKE ALL FROM authenticated.
--   try_acquire_idempotency_key is SECURITY INVOKER — it runs as the calling
--   user, not postgres. Revoking table grants causes 42501 for every client
--   call, blocking plan_declarations inserts.
--
--   Restore the grants originally applied by 20260606000001.
--
-- INVARIANTS:
--   INV-DATA-API-GRANT — authenticated requires SELECT/INSERT/UPDATE for
--   SECURITY INVOKER RPCs that touch this table.
--   DELETE intentionally NOT granted — trg_idempotency_no_delete_processing
--   blocks deletion of 'processing' keys (INV-33).
-- =============================================================================

GRANT SELECT, INSERT, UPDATE ON TABLE public.idempotency_keys TO authenticated;

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
  RAISE NOTICE '✅ idempotency_keys grants restored for authenticated';
END
$$;
