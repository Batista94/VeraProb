-- =============================================================================
-- Migration: INV-6 Hardening Sweep — Runtime Assertion
--
-- Fails if ANY column in public schema uses 'timestamp without time zone'. -- pr_scanner: ignore
-- Acts as a CI gate: future migrations that introduce bare TIMESTAMP will
-- cause this assertion to fail on re-apply (idempotent safety net).
-- =============================================================================

SET client_min_messages TO 'WARNING';

DO $$
DECLARE
  v_violations TEXT;
BEGIN
  SELECT string_agg(table_name || '.' || column_name, ', ')
    INTO v_violations
    FROM information_schema.columns
   WHERE table_schema = 'public'
     AND data_type = 'timestamp without time zone'; -- pr_scanner: ignore

  IF v_violations IS NOT NULL THEN
    RAISE EXCEPTION 'INV-6 VIOLATION: bare timestamp columns found: %', v_violations;
  END IF;
END;
$$;
