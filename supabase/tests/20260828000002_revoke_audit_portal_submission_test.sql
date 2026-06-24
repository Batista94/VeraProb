BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(1);

-- =============================================================================
-- pgTAP: revoke_audit_portal_submission
-- Migration under test: 20260828000002_revoke_audit_portal_submission.sql
-- =============================================================================

SELECT ok(
  NOT EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'audit_portal_submission'
  ),
  'FUNCTION_REMOVED: audit_portal_submission was successfully dropped'
);

SELECT * FROM finish();
ROLLBACK;
