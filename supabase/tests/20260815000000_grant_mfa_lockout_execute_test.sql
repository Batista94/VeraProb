BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(9);

-- =============================================================================
-- pgTAP: MFA lockout RPC EXECUTE grants — regression for 42501
-- Migration: 20260815000000_grant_mfa_lockout_execute.sql
-- Focus: authenticated + service_role can EXECUTE the three MFA circuit-breaker
-- RPCs; anon stays revoked (security intent of 20260717000002 preserved).
-- =============================================================================

-- ── authenticated holds EXECUTE on all three RPCs ────────────────────────────
SELECT ok(
  has_function_privilege('authenticated', 'public.record_mfa_failure(uuid)', 'EXECUTE'),
  'T1: authenticated can EXECUTE record_mfa_failure (app MFA verify path)'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.reset_mfa_lockout(uuid)', 'EXECUTE'),
  'T2: authenticated can EXECUTE reset_mfa_lockout'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.check_mfa_lockout(uuid)', 'EXECUTE'),
  'T3: authenticated can EXECUTE check_mfa_lockout'
);

-- ── service_role holds EXECUTE on all three RPCs ─────────────────────────────
SELECT ok(
  has_function_privilege('service_role', 'public.record_mfa_failure(uuid)', 'EXECUTE'),
  'T4: service_role can EXECUTE record_mfa_failure (super-admin-proxy path)'
);
SELECT ok(
  has_function_privilege('service_role', 'public.reset_mfa_lockout(uuid)', 'EXECUTE'),
  'T5: service_role can EXECUTE reset_mfa_lockout'
);
SELECT ok(
  has_function_privilege('service_role', 'public.check_mfa_lockout(uuid)', 'EXECUTE'),
  'T6: service_role can EXECUTE check_mfa_lockout'
);

-- ── anon stays revoked (INV-2 — no unauthenticated circuit-breaker drive) ────
SELECT ok(
  NOT has_function_privilege('anon', 'public.record_mfa_failure(uuid)', 'EXECUTE'),
  'T7: anon CANNOT EXECUTE record_mfa_failure'
);
SELECT ok(
  NOT has_function_privilege('anon', 'public.reset_mfa_lockout(uuid)', 'EXECUTE'),
  'T8: anon CANNOT EXECUTE reset_mfa_lockout'
);
SELECT ok(
  NOT has_function_privilege('anon', 'public.check_mfa_lockout(uuid)', 'EXECUTE'),
  'T9: anon CANNOT EXECUTE check_mfa_lockout'
);

SELECT * FROM finish();
ROLLBACK;
