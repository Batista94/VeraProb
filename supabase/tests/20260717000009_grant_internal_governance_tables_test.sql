BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test planning
-- 9 tables * 3 assertions (anon, authenticated, service_role) = 27 tests
SELECT plan(27);

-- 1. raw_telemetry_payloads
SELECT table_privs_are('public', 'raw_telemetry_payloads', 'anon', ARRAY[]::text[], 'anon should have NO privileges on raw_telemetry_payloads');
SELECT table_privs_are('public', 'raw_telemetry_payloads', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on raw_telemetry_payloads');
SELECT table_privs_are('public', 'raw_telemetry_payloads', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on raw_telemetry_payloads');

-- 2. asset_status_events
SELECT table_privs_are('public', 'asset_status_events', 'anon', ARRAY[]::text[], 'anon should have NO privileges on asset_status_events');
SELECT table_privs_are('public', 'asset_status_events', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on asset_status_events');
SELECT table_privs_are('public', 'asset_status_events', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on asset_status_events');

-- 3. canonical_facts
SELECT table_privs_are('public', 'canonical_facts', 'anon', ARRAY[]::text[], 'anon should have NO privileges on canonical_facts');
SELECT table_privs_are('public', 'canonical_facts', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on canonical_facts');
SELECT table_privs_are('public', 'canonical_facts', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on canonical_facts');

-- 4. audit_packages
SELECT table_privs_are('public', 'audit_packages', 'anon', ARRAY[]::text[], 'anon should have NO privileges on audit_packages');
SELECT table_privs_are('public', 'audit_packages', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on audit_packages');
SELECT table_privs_are('public', 'audit_packages', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on audit_packages');

-- 5. org_quota_warnings
SELECT table_privs_are('public', 'org_quota_warnings', 'anon', ARRAY[]::text[], 'anon should have NO privileges on org_quota_warnings');
SELECT table_privs_are('public', 'org_quota_warnings', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on org_quota_warnings');
SELECT table_privs_are('public', 'org_quota_warnings', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on org_quota_warnings');

-- 6. ingestion_alerts
SELECT table_privs_are('public', 'ingestion_alerts', 'anon', ARRAY[]::text[], 'anon should have NO privileges on ingestion_alerts');
SELECT table_privs_are('public', 'ingestion_alerts', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on ingestion_alerts');
SELECT table_privs_are('public', 'ingestion_alerts', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on ingestion_alerts');

-- 7. contractual_evaluation_traces
SELECT table_privs_are('public', 'contractual_evaluation_traces', 'anon', ARRAY[]::text[], 'anon should have NO privileges on contractual_evaluation_traces');
-- authenticated SELECT granted intentionally by 20260803000001 (InvestigationModal read).
-- RLS (org_id JWT path) enforces tenant isolation; no write privileges.
SELECT table_privs_are('public', 'contractual_evaluation_traces', 'authenticated', ARRAY['SELECT'], 'authenticated should have SELECT only on contractual_evaluation_traces (read for InvestigationModal)');
SELECT table_privs_are('public', 'contractual_evaluation_traces', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contractual_evaluation_traces');

-- 8. contractual_financial_snapshot_v2
SELECT table_privs_are('public', 'contractual_financial_snapshot_v2', 'anon', ARRAY[]::text[], 'anon should have NO privileges on contractual_financial_snapshot_v2');
SELECT table_privs_are('public', 'contractual_financial_snapshot_v2', 'authenticated', ARRAY[]::text[], 'authenticated should have NO privileges on contractual_financial_snapshot_v2');
SELECT table_privs_are('public', 'contractual_financial_snapshot_v2', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contractual_financial_snapshot_v2');

-- 9. execution_state_transitions
SELECT table_privs_are('public', 'execution_state_transitions', 'anon', ARRAY[]::text[], 'anon should have NO privileges on execution_state_transitions');
SELECT table_privs_are('public', 'execution_state_transitions', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated should have SELECT and INSERT on execution_state_transitions');
SELECT table_privs_are('public', 'execution_state_transitions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on execution_state_transitions');

SELECT * FROM finish();
ROLLBACK;
