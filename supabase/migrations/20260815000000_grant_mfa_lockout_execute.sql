-- =============================================================================
-- Fix: MFA lockout RPCs lost EXECUTE for legitimate callers
-- =============================================================================
-- REASON:
--   20260418000001 created record_mfa_failure / reset_mfa_lockout /
--   check_mfa_lockout relying on the PostgreSQL default EXECUTE grant to PUBLIC.
--   20260717000002 then ran:
--
--     REVOKE EXECUTE ON FUNCTION public.record_mfa_failure(uuid) FROM PUBLIC, anon;
--     (and the two siblings)
--
--   Its header claimed "service_role and authenticated keep their existing
--   grants" — but those grants existed ONLY through PUBLIC. Revoking PUBLIC
--   stripped EXECUTE from EVERY non-owner role (service_role is not a superuser
--   and does not bypass function ACLs). No explicit grant was ever issued, so
--   both legitimate callers broke:
--
--     • super-admin-proxy edge fn  → serviceClient.rpc('check_mfa_lockout')  [service_role]
--     • SupabaseMfaRepository       → _client.rpc('record_mfa_failure', ...)  [authenticated]
--
--   Symptom: 42501 "permission denied for function record_mfa_failure".
--
-- FIX:
--   Grant EXECUTE explicitly to the two roles that legitimately call these RPCs.
--   anon stays revoked (the security intent of 20260717000002 is preserved):
--   unauthenticated callers must never drive the MFA circuit breaker.
--
-- INVARIANTS:
--   INV-1  — callers act on their own auth.uid()-scoped user row only.
--   INV-2  — anon remains unable to invoke (no JWT 'sub' bypass surface).
--   INV-DATA-API-GRANT — explicit grants, no ALTER DEFAULT PRIVILEGES to PUBLIC.
-- =============================================================================

BEGIN;

GRANT EXECUTE ON FUNCTION public.record_mfa_failure(uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.reset_mfa_lockout(uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.check_mfa_lockout(uuid)
  TO authenticated, service_role;

COMMIT;
