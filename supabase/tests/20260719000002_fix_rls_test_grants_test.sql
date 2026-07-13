BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

-- 2 tables * 3 roles = 6 assertions
SELECT plan(6);

-- 1. execution_state_transitions
SELECT table_privs_are('public', 'execution_state_transitions', 'anon', ARRAY[]::text[], 'anon has no privileges on execution_state_transitions');
SELECT table_privs_are('public', 'execution_state_transitions', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated has SELECT and INSERT on execution_state_transitions');
SELECT table_privs_are('public', 'execution_state_transitions', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL on execution_state_transitions');

-- 2. spoofing_audit_entries
SELECT table_privs_are('public', 'spoofing_audit_entries', 'anon', ARRAY[]::text[], 'anon has no privileges on spoofing_audit_entries');
SELECT table_privs_are('public', 'spoofing_audit_entries', 'authenticated', ARRAY[]::text[], 'authenticated has no privileges on quarantined spoofing_audit_entries');
SELECT table_privs_are('public', 'spoofing_audit_entries', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL on spoofing_audit_entries');

SELECT * FROM finish();
ROLLBACK;
