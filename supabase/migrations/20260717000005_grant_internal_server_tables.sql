-- Migration: Explicit Data API Grants for Category C (Internal / Server-Only Tables)
-- Rule: INV-DATA-API-GRANT (Tables in public schema must explicitly grant API role access)
-- Target: service_role (ALL), none for anon and authenticated

-- 1. org_api_secrets
REVOKE ALL ON TABLE public.org_api_secrets FROM anon, authenticated;
GRANT ALL ON TABLE public.org_api_secrets TO service_role;

-- 2. super_admin_users
REVOKE ALL ON TABLE public.super_admin_users FROM anon, authenticated;
GRANT ALL ON TABLE public.super_admin_users TO service_role;

-- 3. super_admin_mfa_lockouts
REVOKE ALL ON TABLE public.super_admin_mfa_lockouts FROM anon, authenticated;
GRANT ALL ON TABLE public.super_admin_mfa_lockouts TO service_role;

-- 4. super_admin_recovery_codes
REVOKE ALL ON TABLE public.super_admin_recovery_codes FROM anon, authenticated;
GRANT ALL ON TABLE public.super_admin_recovery_codes TO service_role;

-- 5. super_admin_access_log
REVOKE ALL ON TABLE public.super_admin_access_log FROM anon, authenticated;
GRANT ALL ON TABLE public.super_admin_access_log TO service_role;

-- 6. impersonation_sessions
REVOKE ALL ON TABLE public.impersonation_sessions FROM anon, authenticated;
GRANT ALL ON TABLE public.impersonation_sessions TO service_role;

-- 7. tenant_billing_events
REVOKE ALL ON TABLE public.tenant_billing_events FROM anon, authenticated;
GRANT ALL ON TABLE public.tenant_billing_events TO service_role;

-- 8. system_audit_log
REVOKE ALL ON TABLE public.system_audit_log FROM anon, authenticated;
GRANT ALL ON TABLE public.system_audit_log TO service_role;

-- 9. forensic_throttle_state
REVOKE ALL ON TABLE public.forensic_throttle_state FROM anon, authenticated;
GRANT ALL ON TABLE public.forensic_throttle_state TO service_role;

-- 10. forensic_throttle_events
REVOKE ALL ON TABLE public.forensic_throttle_events FROM anon, authenticated;
GRANT ALL ON TABLE public.forensic_throttle_events TO service_role;

-- 11. idempotency_keys
REVOKE ALL ON TABLE public.idempotency_keys FROM anon, authenticated;
GRANT ALL ON TABLE public.idempotency_keys TO service_role;

-- 12. justification_recomputation_signals
REVOKE ALL ON TABLE public.justification_recomputation_signals FROM anon, authenticated;
GRANT ALL ON TABLE public.justification_recomputation_signals TO service_role;

-- 13. evidence_deletion_queue
REVOKE ALL ON TABLE public.evidence_deletion_queue FROM anon, authenticated;
GRANT ALL ON TABLE public.evidence_deletion_queue TO service_role;

-- 14. justification_audit_logs
REVOKE ALL ON TABLE public.justification_audit_logs FROM anon, authenticated;
GRANT ALL ON TABLE public.justification_audit_logs TO service_role;

-- 15. sanction_escalation_log
REVOKE ALL ON TABLE public.sanction_escalation_log FROM anon, authenticated;
GRANT ALL ON TABLE public.sanction_escalation_log TO service_role;

-- 16. spoofing_audit_entries
REVOKE ALL ON TABLE public.spoofing_audit_entries FROM anon, authenticated;
GRANT ALL ON TABLE public.spoofing_audit_entries TO service_role;

-- 17. trips_audit
REVOKE ALL ON TABLE public.trips_audit FROM anon, authenticated;
GRANT ALL ON TABLE public.trips_audit TO service_role;

-- 18. shadow_executions
REVOKE ALL ON TABLE public.shadow_executions FROM anon, authenticated;
GRANT ALL ON TABLE public.shadow_executions TO service_role;

-- 19. shadow_execution_transitions
REVOKE ALL ON TABLE public.shadow_execution_transitions FROM anon, authenticated;
GRANT ALL ON TABLE public.shadow_execution_transitions TO service_role;

-- 20. shadow_verdicts
REVOKE ALL ON TABLE public.shadow_verdicts FROM anon, authenticated;
GRANT ALL ON TABLE public.shadow_verdicts TO service_role;

-- 21. telegram_evidence_categories
REVOKE ALL ON TABLE public.telegram_evidence_categories FROM anon, authenticated;
GRANT ALL ON TABLE public.telegram_evidence_categories TO service_role;
