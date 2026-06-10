BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test planning
-- 8 tables * 2 assertions (one for authenticated, one for service_role) = 16 tests
SELECT plan(16);

-- 1. organizations — trust root: authenticated read-only; writes via SECURITY DEFINER
--    RPCs only. INSERT/UPDATE/DELETE revoked in 20260811000001_harden_identity_trust_roots.
SELECT table_privs_are('public', 'organizations', 'authenticated', ARRAY['SELECT'], 'authenticated should have SELECT-only on organizations (trust root)');
SELECT table_privs_are('public', 'organizations', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on organizations');

-- 2. user_roles — organization_id claim source: authenticated read-only; writes via
--    SECURITY DEFINER RPCs only. INSERT/UPDATE/DELETE revoked in 20260811000001.
SELECT table_privs_are('public', 'user_roles', 'authenticated', ARRAY['SELECT'], 'authenticated should have SELECT-only on user_roles (claim trust root)');
SELECT table_privs_are('public', 'user_roles', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on user_roles');

-- 3. drivers
SELECT table_privs_are('public', 'drivers', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on drivers');
SELECT table_privs_are('public', 'drivers', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on drivers');

-- 4. invitations
SELECT table_privs_are('public', 'invitations', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on invitations');
SELECT table_privs_are('public', 'invitations', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on invitations');

-- 5. provider_api_keys
SELECT table_privs_are('public', 'provider_api_keys', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on provider_api_keys');
SELECT table_privs_are('public', 'provider_api_keys', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on provider_api_keys');

-- 6. csv_mapping_templates
SELECT table_privs_are('public', 'csv_mapping_templates', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on csv_mapping_templates');
SELECT table_privs_are('public', 'csv_mapping_templates', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on csv_mapping_templates');

-- 7. sla_templates
SELECT table_privs_are('public', 'sla_templates', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on sla_templates');
SELECT table_privs_are('public', 'sla_templates', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on sla_templates');

-- 8. sla_audit_ledger
SELECT table_privs_are('public', 'sla_audit_ledger', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'], 'authenticated should have CRUD on sla_audit_ledger');
SELECT table_privs_are('public', 'sla_audit_ledger', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on sla_audit_ledger');

SELECT * FROM finish();
ROLLBACK;
