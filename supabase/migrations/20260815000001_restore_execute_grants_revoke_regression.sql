-- =============================================================================
-- Fix: super_admin_* / invitation / E2E-helper RPCs lost EXECUTE for legitimate
--      callers (same class as 20260815000000, but the full regression surface).
-- =============================================================================
-- REASON:
--   20260717000002 ("fix_anon_function_execute_revoke") ran, for a large set of
--   SECURITY DEFINER functions:
--
--     REVOKE EXECUTE ON FUNCTION public.<fn>(...) FROM PUBLIC, anon;
--
--   Its header claimed "service_role and authenticated keep their existing
--   grants" — but for many of these functions EXECUTE was held ONLY through the
--   PostgreSQL default grant to PUBLIC. service_role is NOT a superuser in the
--   Supabase stack and does NOT bypass function ACLs, so revoking PUBLIC stripped
--   EXECUTE from every non-owner role that lacked an explicit grant. The earlier
--   service_role-bypass migrations recreated several of these functions (which
--   resets the ACL), so by the final migration state the explicit service_role
--   grant was gone. super_admin_archive_organization additionally lost
--   `authenticated` (it never carried an explicit authenticated grant).
--
--   Symptoms (CI, fresh `db reset`):
--     • Coverage Gate / accept_invitation race  → service_role 42501
--     • SuperAdmin E2E Gate / super_admin_create_organization (bootstrap, service_role)
--     • SuperAdmin E2E Gate / super_admin_archive_organization (UI path, authenticated)
--       → archive silently fails, org stays ACTIVE, audit log empty (52 cascade)
--
-- FIX:
--   Restore EXECUTE for the roles each function legitimately needs, matching the
--   pre-revoke intent. anon stays revoked (the security goal of 20260717000002
--   is preserved). All super_admin_* functions self-guard on the super_admin JWT
--   claim, so granting `authenticated` exposes no privilege escalation.
--
--   Scope deliberately EXCLUDES:
--     • trigger functions (invoked by the trigger mechanism, never RPC-called)
--     • internal `_`-prefixed helpers (owner-only by design)
--     • Phase 10.6 dispute RPCs (resolve_dispute / reject_sanction /
--       confirm_peer_review / approve_sanction / dispute_sanction /
--       decline_peer_review / attach_dispute_evidence / *_dispute_portal_token /
--       read_dispute_portal) — these intentionally revoke service_role and are
--       authenticated/anon-only by design.
--
--   test_* helpers receive service_role ONLY (never authenticated): they are
--   E2E/CI fixtures driven by the service_role harness and must remain
--   unreachable by ordinary tenant users in production.
--
-- INVARIANTS:
--   INV-1  — functions enforce org_id / super_admin scoping internally.
--   INV-2  — anon remains unable to invoke (no JWT 'sub' bypass surface).
--   INV-22 — cross-tenant guards unchanged; only trusted roles regain EXECUTE.
--   INV-DATA-API-GRANT — explicit grants, no ALTER DEFAULT PRIVILEGES to PUBLIC.
--
-- pr_scanner: ignore-regression — additive GRANT-only remediation. No DDL, no
--   forensic-logic change; restores EXECUTE that 20260717000002 collaterally
--   stripped (same class as 20260815000000). anon stays revoked; dispute RPCs
--   stay service_role-locked. QA-Security reviewed (CIA: super_admin_* self-guard
--   on the super_admin JWT claim; test_* helpers service_role-only).
-- =============================================================================

BEGIN;

-- ── super_admin_* family (authenticated app path + service_role harness/edge) ──
GRANT EXECUTE ON FUNCTION public.super_admin_create_organization(
  text, text, text, text, text, text, integer, integer, uuid,
  jsonb, integer, integer, integer, text, text, text, text, text[])
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_archive_organization(uuid, text, uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_unarchive_organization(uuid, text, uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_update_organization_quota(
  uuid, text, integer, integer, uuid, text, jsonb, bigint, integer, smallint,
  text, text, text, text, text, timestamp with time zone)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_add_org_admin(
  uuid, text, uuid, uuid, timestamp with time zone, uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_add_org_admin(
  uuid, text, uuid, uuid, timestamp with time zone, uuid, text)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_invite_first_admin(
  uuid, text, text, text, uuid, timestamp with time zone, uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_get_org_members(uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_check_cnpj_exists(text)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_revoke_invitation(uuid, text, uuid, text)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_toggle_member_status(uuid, uuid, boolean)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_update_allowed_domains(uuid, text[], uuid, text)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.super_admin_audit_resend_invitation(uuid, text, text)
  TO authenticated, service_role;

-- ── Token-driven flows (anon kept; restore authenticated + service_role) ───────
GRANT EXECUTE ON FUNCTION public.accept_invitation(text, uuid)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.accept_contract_by_contractor(text)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_contract_for_review(text)
  TO authenticated, service_role;

-- ── Idempotency cleanup (authenticated app path; service_role already holds) ──
-- 20260717000002 stripped its PUBLIC-only authenticated grant; 20260606000001
-- expects authenticated to retain EXECUTE "in final schema".
GRANT EXECUTE ON FUNCTION public.cleanup_expired_idempotency(integer)
  TO authenticated, service_role;

-- ── E2E / CI helpers (service_role ONLY — never reachable by tenant users) ─────
GRANT EXECUTE ON FUNCTION public.test_archive_org_for_e2e(uuid)
  TO service_role;

GRANT EXECUTE ON FUNCTION public.test_cleanup_forensic_data(uuid)
  TO service_role;

GRANT EXECUTE ON FUNCTION public.test_cleanup_system_audit_log(uuid[])
  TO service_role;

GRANT EXECUTE ON FUNCTION public.test_get_user_banned_until(uuid)
  TO service_role;

GRANT EXECUTE ON FUNCTION public.test_tamper_raw_telemetry_payload(uuid, jsonb)
  TO service_role;

COMMIT;
