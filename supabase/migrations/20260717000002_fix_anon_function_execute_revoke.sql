-- =============================================================================
-- Fix: anon_security_definer_function_executable (Supabase linter 0027)
-- =============================================================================
-- REASON:
--   All SECURITY DEFINER functions in public.* are callable by the `anon` role
--   by default. Anon has no JWT 'sub' claim. Multiple super_admin_* functions
--   guard access with:
--
--     IF (auth.jwt() ->> 'sub') IS NOT NULL THEN
--       -- check super_admin claim
--     END IF;
--
--   When called as anon, auth.jwt() ->> 'sub' IS NULL → the entire guard is
--   SKIPPED → unauthenticated callers can invoke super_admin_archive_organization,
--   super_admin_create_organization, etc. without any authentication.
--
--   This migration revokes EXECUTE from PUBLIC and anon on all SECURITY DEFINER
--   functions that must not be callable by unauthenticated users. Service_role
--   and authenticated keep their existing grants. SECURITY DEFINER functions
--   run as the owner (postgres), so they still access internal tables regardless
--   of the calling role's table-level ACL.
--
-- FUNCTIONS KEPT FOR ANON (required for unauthenticated flows):
--   accept_contract_by_contractor(text)  — contractor URL token flow
--   get_contract_for_review(text)        — contractor review page
--   accept_invitation(text, uuid)        — invitation acceptance flow
--   custom_access_token_hook(jsonb)      — Supabase Auth JWT hook
--
-- INVARIANTS:
--   INV-1  — org_id filter enforced; anon bypass eliminated.
--   INV-2  — auth.jwt() guard now unconditionally reached.
--   INV-22 — cross-tenant operations blocked at auth layer for unauthenticated.
--   INV-28 — org secret operations (create_organization) no longer anon-callable.
-- =============================================================================

-- ── super_admin_* functions ───────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.super_admin_create_organization(
  text, text, text, text, text, text, integer, integer, uuid,
  jsonb, integer, integer, integer, text, text, text, text, text[]
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_archive_organization(uuid, text, uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_unarchive_organization(uuid, text, uuid)
  FROM PUBLIC, anon;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT oid::regprocedure AS sig
      FROM pg_proc
     WHERE proname = 'super_admin_update_organization_quota'
  ) LOOP
    EXECUTE 'REVOKE EXECUTE ON FUNCTION ' || r.sig || ' FROM PUBLIC, anon';
  END LOOP;
END $$;

REVOKE EXECUTE ON FUNCTION public.super_admin_add_org_admin(
  uuid, text, uuid, uuid, timestamp with time zone, uuid
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_add_org_admin(
  uuid, text, uuid, uuid, timestamp with time zone, uuid, text
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_invite_first_admin(
  uuid, text, text, text, uuid, timestamp with time zone, uuid
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_get_org_members(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_check_cnpj_exists(text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_revoke_invitation(uuid, text, uuid, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_toggle_member_status(uuid, uuid, boolean)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_update_allowed_domains(uuid, text[], uuid, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.super_admin_audit_resend_invitation(uuid, text, text)
  FROM PUBLIC, anon;

-- ── test_* functions (E2E helpers — must never be anon-callable in production) ─

REVOKE EXECUTE ON FUNCTION public.test_cleanup_forensic_data(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.test_archive_org_for_e2e(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.test_tamper_raw_telemetry_payload(uuid, jsonb)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.test_cleanup_system_audit_log(uuid[])
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.test_get_user_banned_until(uuid)
  FROM PUBLIC, anon;

-- ── Infrastructure / internal RPC functions ───────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.notify_pgrst_reload()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_schema_integrity(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_rls_enabled(text)
  FROM PUBLIC, anon;

-- ── Member management ─────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.offboard_driver(uuid, uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.deactivate_member(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.reactivate_member(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.remove_member(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.update_member_role(uuid, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.invite_user(text, text, text, timestamp with time zone, uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.revoke_invitation(uuid)
  FROM PUBLIC, anon;

-- ── MFA lockout management ────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.record_mfa_failure(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.reset_mfa_lockout(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_mfa_lockout(uuid)
  FROM PUBLIC, anon;

-- ── Audit / reporting ─────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.generate_monthly_audit_package(uuid, integer, integer, uuid)
  FROM PUBLIC, anon;

-- ── Execution / operational RPCs ─────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.create_execution_for_operator(
  uuid, text, uuid, uuid, uuid, uuid, timestamp with time zone, timestamp with time zone
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.complete_execution(uuid, text, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_and_close_execution_autonomously(
  uuid, text, double precision, double precision, timestamp with time zone
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_execution_compliance(uuid, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.start_transit_for_execution(uuid, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.process_gps_for_execution_transitions(
  uuid, text, double precision, double precision, timestamp with time zone
) FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_batch_compliance_status(uuid, text[])
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_trip_compliance_status(uuid, uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_driver_status_query_count(uuid, uuid, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_missed_facts(uuid, timestamp with time zone, integer)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_device_heartbeat_status(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.find_execution_for_telegram(uuid, uuid, bigint)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.find_pending_trips_for_driver(uuid, uuid, integer)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_rule_version_history(uuid)
  FROM PUBLIC, anon;

-- ── Shadow / Telegram ─────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.create_shadow_execution(uuid, uuid, bigint, uuid, bigint, bigint)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.consume_telegram_binding_token(text, bigint)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_telegram_rate_limit(bigint)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.resolve_telegram_orphan_with_link(text, uuid)
  FROM PUBLIC, anon;

-- ── Contract RPCs ─────────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.submit_contract_for_approval(uuid, uuid, text, timestamp with time zone)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.submit_contract_for_approval(uuid, uuid, text, timestamp with time zone, bigint)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.update_contractual_rule(uuid, uuid, sla_rule_type, jsonb, integer, timestamp with time zone)
  FROM PUBLIC, anon;

-- ── Justification ─────────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.update_justification_status_with_audit(uuid, uuid, text, text, text, text[])
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.use_justification_token(uuid, text, text)
  FROM PUBLIC, anon;

-- ── Asset / quota ─────────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.get_current_asset_status(uuid, uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_pending_sanctions_count(uuid)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.get_org_members()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_idempotency(integer)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.mark_alert_viewed(uuid, uuid)
  FROM PUBLIC, anon;

-- ── SECURITY DEFINER trigger functions ───────────────────────────────────────
-- Trigger functions should NEVER be directly called; only the trigger mechanism
-- invokes them. Revoking EXECUTE prevents any direct RPC call.

REVOKE EXECUTE ON FUNCTION public._edq_block_delete_after_update()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.auto_enqueue_sanction_recommended()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.auto_log_shadow_transition()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.check_vehicle_quota_warning()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.enforce_contract_quota()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.enforce_vehicle_quota()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.fn_user_roles_populate_denorm()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.inhibit_execution_on_justification_approval()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.recalc_vehicle_quota_warning_on_update()
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.seal_forensic_record()
  FROM PUBLIC, anon;

-- ── PostGIS functions in public schema ────────────────────────────────────────
-- These are geometry functions that ended up in public due to PostGIS install.
-- Anon has no legitimate use for these.

REVOKE EXECUTE ON FUNCTION public.st_estimatedextent(text, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.st_estimatedextent(text, text, text)
  FROM PUBLIC, anon;

REVOKE EXECUTE ON FUNCTION public.st_estimatedextent(text, text, text, boolean)
  FROM PUBLIC, anon;

-- ── Verify (advisory) ─────────────────────────────────────────────────────────
-- SELECT proname, pg_get_function_identity_arguments(p.oid) AS args,
--        array_to_string(p.proacl, ',') AS acl
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.prosecdef = true
--   AND (
--     array_to_string(p.proacl, ',') LIKE '%=X/%'
--     OR array_to_string(p.proacl, ',') LIKE '%anon=X/%'
--   )
--   AND p.proname NOT IN (
--     'accept_contract_by_contractor',
--     'get_contract_for_review',
--     'accept_invitation',
--     'custom_access_token_hook'
--   )
-- ORDER BY proname;
-- Expected: 0 rows
