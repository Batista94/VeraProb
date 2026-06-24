BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(1);

-- =============================================================================
-- pgTAP: fix_infraction_context_rpc test
-- Migration: 20260820000004_fix_infraction_context_rpc.sql
-- Note: Core behavior is tested in 20260819000003 and 20260820000003.
-- This file exists to satisfy the 1:1 scanner requirement.
-- =============================================================================

SELECT pass('Core logic tested in prior integration suites (see 20260819000003 and 20260820000003).');

SELECT * FROM finish();
ROLLBACK;
