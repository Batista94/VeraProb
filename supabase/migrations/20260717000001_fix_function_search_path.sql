-- =============================================================================
-- Fix: function_search_path_mutable (Supabase linter 0029)
-- =============================================================================
-- REASON:
--   PostgreSQL functions without a fixed search_path inherit the session
--   search_path at call time. A malicious caller (or compromised session) could
--   inject a schema early in the search_path and redirect unqualified references
--   (e.g. NOW(), gen_random_uuid(), table names) to attacker-controlled objects.
--   SECURITY DEFINER functions are the highest-risk category: they run as the
--   function OWNER (postgres), so a hijacked lookup executes with superuser
--   privileges.
--
--   Fix: ALTER FUNCTION ... SET search_path = 'public' (or 'public, auth,
--   extensions' for SECURITY DEFINER functions that call auth.* / extensions.*).
--   Zero-downtime: ALTER FUNCTION acquires only ShareUpdateExclusiveLock.
--   No function is recreated; body/signature/ACL unchanged.
--
-- INVARIANTS:
--   INV-2  — prevents search_path hijack on RLS-adjacent trigger functions.
--   INV-22 — tenant isolation guards can no longer be hijacked via schema squatting.
-- =============================================================================

-- ── Non-SECURITY DEFINER functions — SET search_path = 'public' ──────────────

ALTER FUNCTION public._bump_version_trigger_fn()
  SET search_path = 'public';

ALTER FUNCTION public.auto_link_shadows_to_execution()
  SET search_path = 'public';

ALTER FUNCTION public.batch_update_contracts(jsonb)
  SET search_path = 'public';

ALTER FUNCTION public.batch_update_vehicles(jsonb)
  SET search_path = 'public';

ALTER FUNCTION public.block_throttle_events_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.complete_idempotency_key(text, text, integer, jsonb)
  SET search_path = 'public';

ALTER FUNCTION public.csv_mapping_template_version_bump()
  SET search_path = 'public';

ALTER FUNCTION public.fail_idempotency_key(text, text, integer, jsonb)
  SET search_path = 'public';

ALTER FUNCTION public.fn_shadow_verdicts_immutable()
  SET search_path = 'public';

ALTER FUNCTION public.fsm_guard_terminal_states()
  SET search_path = 'public';

ALTER FUNCTION public.get_auth_role()
  SET search_path = 'public';

ALTER FUNCTION public.guard_shadow_execution_transitions()
  SET search_path = 'public';

ALTER FUNCTION public.impersonation_sessions_immutability_guard()
  SET search_path = 'public';

ALTER FUNCTION public.impersonation_sessions_max_one_active()
  SET search_path = 'public';

ALTER FUNCTION public.mask_cnpj(text)
  SET search_path = 'public';

ALTER FUNCTION public.mask_email(text)
  SET search_path = 'public';

ALTER FUNCTION public.org_api_secrets_immutability_guard()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_audit_log_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_billing_event_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_cj_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_cj_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_contractual_snapshot_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_deletion_of_audited_trip()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_idempotency_key_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_idempotency_processing_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_immutable_update()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_jeu_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_jrs_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_jrs_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_jst_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_jst_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_ledger_v1_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_ledger_v2_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_sel_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_sel_update()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_srq_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_srq_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tbt_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tbt_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tcb_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tcb_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tec_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tec_update()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tel_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tel_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tem_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tem_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_teu_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_teu_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tsq_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tsq_update()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tuc_delete()
  SET search_path = 'public';

ALTER FUNCTION public.prevent_tuc_immutable_mutation()
  SET search_path = 'public';

ALTER FUNCTION public.set_updated_at()
  SET search_path = 'public';

ALTER FUNCTION public.strict_tenant_envelope_validation()
  SET search_path = 'public';

ALTER FUNCTION public.suppress_flood_alerts()
  SET search_path = 'public';

ALTER FUNCTION public.system_audit_log_governance_check()
  SET search_path = 'public';

ALTER FUNCTION public.trg_teu_mime_type_not_null()
  SET search_path = 'public';

ALTER FUNCTION public.try_acquire_idempotency_key(text, text, text, uuid, integer)
  SET search_path = 'public';

ALTER FUNCTION public.vp_haversine_meters(double precision, double precision, double precision, double precision)
  SET search_path = 'public';

ALTER FUNCTION public.vp_kinematic_guard()
  SET search_path = 'public';

-- ── SECURITY DEFINER functions — SET search_path = 'public, auth, extensions' ─
-- These run as the function owner (postgres). Fixed search_path prevents
-- schema-squatting attacks where an attacker creates a shadow schema that
-- intercepts auth.jwt() / extensions.gen_random_bytes() / table lookups.

ALTER FUNCTION public._edq_block_delete_after_update()
  SET search_path = 'public, auth, extensions';

ALTER FUNCTION public.auto_enqueue_sanction_recommended()
  SET search_path = 'public, auth, extensions';

ALTER FUNCTION public.create_execution_for_operator(
  uuid, text, uuid, uuid, uuid, uuid, timestamp with time zone, timestamp with time zone
)
  SET search_path = 'public, auth, extensions';

ALTER FUNCTION public.custom_access_token_hook(jsonb)
  SET search_path = 'public, auth, extensions';

ALTER FUNCTION public.get_current_asset_status(uuid, uuid)
  SET search_path = 'public, auth, extensions';

ALTER FUNCTION public.get_pending_sanctions_count(uuid)
  SET search_path = 'public, auth, extensions';

-- ── Verify (advisory — run manually after deploy) ─────────────────────────────
-- SELECT proname, proconfig
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
--   AND NOT EXISTS (
--     SELECT 1 FROM pg_options_to_table(p.proconfig) WHERE option_name = 'search_path'
--   )
-- ORDER BY proname;
-- Expected: 0 rows
