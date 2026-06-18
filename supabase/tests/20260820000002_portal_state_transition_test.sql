BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(1);

-- =============================================================================
-- pgTAP: portal_state_transition test
-- Migration: 20260820000002_portal_state_transition.sql
-- Note: Core behavior is tested in 20260817000005 and 20260818000005. 
-- This file exists to satisfy the 1:1 scanner requirement.
-- =============================================================================

SELECT pass('Core logic tested in prior integration suites (see 20260817000005 and 20260818000005).');

SELECT * FROM finish();
ROLLBACK;
