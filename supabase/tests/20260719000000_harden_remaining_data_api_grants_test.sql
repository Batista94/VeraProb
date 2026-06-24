BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

-- 3 tables * 3 roles + 3 views * 3 roles = 18 assertions
SELECT plan(18);

-- 1. pdf_dossier_logs
SELECT table_privs_are('public', 'pdf_dossier_logs', 'anon', ARRAY[]::text[], 'anon has no privileges on pdf_dossier_logs');
SELECT table_privs_are('public', 'pdf_dossier_logs', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated has SELECT and INSERT on pdf_dossier_logs');
SELECT table_privs_are('public', 'pdf_dossier_logs', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL on pdf_dossier_logs');

-- 2. shadow_mode_simulations
SELECT table_privs_are('public', 'shadow_mode_simulations', 'anon', ARRAY[]::text[], 'anon has no privileges on shadow_mode_simulations');
SELECT table_privs_are('public', 'shadow_mode_simulations', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated has SELECT and INSERT on shadow_mode_simulations');
SELECT table_privs_are('public', 'shadow_mode_simulations', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL on shadow_mode_simulations');

-- 3. telegram_status_queries
SELECT table_privs_are('public', 'telegram_status_queries', 'anon', ARRAY[]::text[], 'anon has no privileges on telegram_status_queries');
SELECT table_privs_are('public', 'telegram_status_queries', 'authenticated', ARRAY['SELECT', 'INSERT'], 'authenticated has SELECT and INSERT on telegram_status_queries');
SELECT table_privs_are('public', 'telegram_status_queries', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL on telegram_status_queries');

-- 4. contractors_view
SELECT table_privs_are('public', 'contractors_view', 'anon', ARRAY[]::text[], 'anon has no privileges on contractors_view');
SELECT table_privs_are('public', 'contractors_view', 'authenticated', ARRAY['SELECT'], 'authenticated has SELECT on contractors_view');
SELECT table_privs_are('public', 'contractors_view', 'service_role', ARRAY['SELECT'], 'service_role has SELECT only on contractors_view (read-only PII view, least privilege — 20260815000002)');

-- 5. invitations_view
SELECT table_privs_are('public', 'invitations_view', 'anon', ARRAY[]::text[], 'anon has no privileges on invitations_view');
SELECT table_privs_are('public', 'invitations_view', 'authenticated', ARRAY['SELECT'], 'authenticated has SELECT on invitations_view');
SELECT table_privs_are('public', 'invitations_view', 'service_role', ARRAY['SELECT'], 'service_role has SELECT only on invitations_view (read-only PII view, least privilege — 20260815000002)');

-- 6. v_roi_summary
SELECT table_privs_are('public', 'v_roi_summary', 'anon', ARRAY[]::text[], 'anon has no privileges on v_roi_summary');
SELECT table_privs_are('public', 'v_roi_summary', 'authenticated', ARRAY['SELECT'], 'authenticated has SELECT on v_roi_summary');
SELECT table_privs_are('public', 'v_roi_summary', 'service_role', ARRAY['SELECT'], 'service_role has SELECT only on v_roi_summary (read-only summary view, least privilege — 20260815000002)');

SELECT * FROM finish();
ROLLBACK;
