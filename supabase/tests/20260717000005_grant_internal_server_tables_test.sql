BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test planning
-- 21 tables * 3 assertions = 63 tests
SELECT plan(63);

-- 1. org_api_secrets
SELECT table_privs_are('public', 'org_api_secrets', 'anon', ARRAY[]::text[], 'anon should have no privileges on org_api_secrets');
SELECT table_privs_are('public', 'org_api_secrets', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on org_api_secrets');
SELECT table_privs_are('public', 'org_api_secrets', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on org_api_secrets');

-- 2. super_admin_users
SELECT table_privs_are('public', 'super_admin_users', 'anon', ARRAY[]::text[], 'anon should have no privileges on super_admin_users');
SELECT table_privs_are('public', 'super_admin_users', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on super_admin_users');
SELECT table_privs_are('public', 'super_admin_users', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on super_admin_users');

-- 3. super_admin_mfa_lockouts
SELECT table_privs_are('public', 'super_admin_mfa_lockouts', 'anon', ARRAY[]::text[], 'anon should have no privileges on super_admin_mfa_lockouts');
SELECT table_privs_are('public', 'super_admin_mfa_lockouts', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on super_admin_mfa_lockouts');
SELECT table_privs_are('public', 'super_admin_mfa_lockouts', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on super_admin_mfa_lockouts');

-- 4. super_admin_recovery_codes
SELECT table_privs_are('public', 'super_admin_recovery_codes', 'anon', ARRAY[]::text[], 'anon should have no privileges on super_admin_recovery_codes');
SELECT table_privs_are('public', 'super_admin_recovery_codes', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on super_admin_recovery_codes');
SELECT table_privs_are('public', 'super_admin_recovery_codes', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on super_admin_recovery_codes');

-- 5. super_admin_access_log
SELECT table_privs_are('public', 'super_admin_access_log', 'anon', ARRAY[]::text[], 'anon should have no privileges on super_admin_access_log');
SELECT table_privs_are('public', 'super_admin_access_log', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on super_admin_access_log');
SELECT table_privs_are('public', 'super_admin_access_log', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on super_admin_access_log');

-- 6. impersonation_sessions
SELECT table_privs_are('public', 'impersonation_sessions', 'anon', ARRAY[]::text[], 'anon should have no privileges on impersonation_sessions');
SELECT table_privs_are('public', 'impersonation_sessions', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on impersonation_sessions');
SELECT table_privs_are('public', 'impersonation_sessions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on impersonation_sessions');

-- 7. tenant_billing_events
SELECT table_privs_are('public', 'tenant_billing_events', 'anon', ARRAY[]::text[], 'anon should have no privileges on tenant_billing_events');
SELECT table_privs_are('public', 'tenant_billing_events', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on tenant_billing_events');
SELECT table_privs_are('public', 'tenant_billing_events', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on tenant_billing_events');

-- 8. system_audit_log
SELECT table_privs_are('public', 'system_audit_log', 'anon', ARRAY[]::text[], 'anon should have no privileges on system_audit_log');
SELECT table_privs_are('public', 'system_audit_log', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on system_audit_log');
SELECT table_privs_are('public', 'system_audit_log', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on system_audit_log');

-- 9. forensic_throttle_state
SELECT table_privs_are('public', 'forensic_throttle_state', 'anon', ARRAY[]::text[], 'anon should have no privileges on forensic_throttle_state');
SELECT table_privs_are('public', 'forensic_throttle_state', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on forensic_throttle_state');
SELECT table_privs_are('public', 'forensic_throttle_state', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on forensic_throttle_state');

-- 10. forensic_throttle_events
SELECT table_privs_are('public', 'forensic_throttle_events', 'anon', ARRAY[]::text[], 'anon should have no privileges on forensic_throttle_events');
SELECT table_privs_are('public', 'forensic_throttle_events', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on forensic_throttle_events');
SELECT table_privs_are('public', 'forensic_throttle_events', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on forensic_throttle_events');

-- 11. idempotency_keys
SELECT table_privs_are('public', 'idempotency_keys', 'anon', ARRAY[]::text[], 'anon should have no privileges on idempotency_keys');
SELECT table_privs_are('public', 'idempotency_keys', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'authenticated should have SELECT, INSERT, and UPDATE privileges on idempotency_keys');
SELECT table_privs_are('public', 'idempotency_keys', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on idempotency_keys');

-- 12. justification_recomputation_signals
SELECT table_privs_are('public', 'justification_recomputation_signals', 'anon', ARRAY[]::text[], 'anon should have no privileges on justification_recomputation_signals');
SELECT table_privs_are('public', 'justification_recomputation_signals', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on justification_recomputation_signals');
SELECT table_privs_are('public', 'justification_recomputation_signals', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on justification_recomputation_signals');

-- 13. evidence_deletion_queue
SELECT table_privs_are('public', 'evidence_deletion_queue', 'anon', ARRAY[]::text[], 'anon should have no privileges on evidence_deletion_queue');
SELECT table_privs_are('public', 'evidence_deletion_queue', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on evidence_deletion_queue');
SELECT table_privs_are('public', 'evidence_deletion_queue', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on evidence_deletion_queue');

-- 14. justification_audit_logs
SELECT table_privs_are('public', 'justification_audit_logs', 'anon', ARRAY[]::text[], 'anon should have no privileges on justification_audit_logs');
SELECT table_privs_are('public', 'justification_audit_logs', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on justification_audit_logs');
SELECT table_privs_are('public', 'justification_audit_logs', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on justification_audit_logs');

-- 15. sanction_escalation_log
SELECT table_privs_are('public', 'sanction_escalation_log', 'anon', ARRAY[]::text[], 'anon should have no privileges on sanction_escalation_log');
SELECT table_privs_are('public', 'sanction_escalation_log', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on sanction_escalation_log');
SELECT table_privs_are('public', 'sanction_escalation_log', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on sanction_escalation_log');

-- 16. spoofing_audit_entries
SELECT table_privs_are('public', 'spoofing_audit_entries', 'anon', ARRAY[]::text[], 'anon should have no privileges on spoofing_audit_entries');
SELECT table_privs_are('public', 'spoofing_audit_entries', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated should have SELECT and INSERT on spoofing_audit_entries');
SELECT table_privs_are('public', 'spoofing_audit_entries', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on spoofing_audit_entries');

-- 17. trips_audit
SELECT table_privs_are('public', 'trips_audit', 'anon', ARRAY[]::text[], 'anon should have no privileges on trips_audit');
SELECT table_privs_are('public', 'trips_audit', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have SELECT, INSERT, UPDATE, and DELETE on trips_audit');
SELECT table_privs_are('public', 'trips_audit', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on trips_audit');

-- 18. shadow_executions
SELECT table_privs_are('public', 'shadow_executions', 'anon', ARRAY[]::text[], 'anon should have no privileges on shadow_executions');
SELECT table_privs_are('public', 'shadow_executions', 'authenticated', ARRAY['SELECT'], 'authenticated should have SELECT on shadow_executions');
SELECT table_privs_are('public', 'shadow_executions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on shadow_executions');

-- 19. shadow_execution_transitions
SELECT table_privs_are('public', 'shadow_execution_transitions', 'anon', ARRAY[]::text[], 'anon should have no privileges on shadow_execution_transitions');
SELECT table_privs_are('public', 'shadow_execution_transitions', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on shadow_execution_transitions');
SELECT table_privs_are('public', 'shadow_execution_transitions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on shadow_execution_transitions');

-- 20. shadow_verdicts
SELECT table_privs_are('public', 'shadow_verdicts', 'anon', ARRAY[]::text[], 'anon should have no privileges on shadow_verdicts');
SELECT table_privs_are('public', 'shadow_verdicts', 'authenticated', ARRAY[]::text[], 'authenticated should have no privileges on shadow_verdicts');
SELECT table_privs_are('public', 'shadow_verdicts', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on shadow_verdicts');

-- 21. telegram_evidence_categories
SELECT table_privs_are('public', 'telegram_evidence_categories', 'anon', ARRAY[]::text[], 'anon should have no privileges on telegram_evidence_categories');
SELECT table_privs_are('public', 'telegram_evidence_categories', 'authenticated', ARRAY['SELECT'], 'authenticated should have SELECT on telegram_evidence_categories');
SELECT table_privs_are('public', 'telegram_evidence_categories', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_evidence_categories');

SELECT * FROM finish();
ROLLBACK;
