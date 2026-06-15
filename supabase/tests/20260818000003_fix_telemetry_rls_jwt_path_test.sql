-- ============================================================
-- Forensic DB Test: Fix Telemetry JWT Path
-- Target: 20260818000003_fix_telemetry_rls_jwt_path.sql
-- ============================================================

BEGIN;

-- Plan count: 2 tests
SELECT plan(2);

-- ── 1. Policy Definition Check: raw_telemetry_payloads ──────
SELECT policies_are(
    'public',
    'raw_telemetry_payloads',
    ARRAY['raw_telemetry_payloads_org_isolation'],
    'Test 1: Policy name is correctly defined on raw_telemetry_payloads.'
);

-- ── 2. Policy Definition Check: canonical_facts ─────────────
SELECT policies_are(
    'public',
    'canonical_facts',
    ARRAY['canonical_facts_org_isolation'],
    'Test 2: Policy name is correctly defined on canonical_facts.'
);

SELECT * FROM finish();

ROLLBACK;
