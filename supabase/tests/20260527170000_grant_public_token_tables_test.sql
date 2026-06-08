BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Test planning
-- 4 tables * 3 assertions = 12 tests
SELECT plan(12);

-- 1. contract_review_tokens
SELECT table_privs_are('public', 'contract_review_tokens', 'anon', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'anon should have SELECT, INSERT, UPDATE on contract_review_tokens');
SELECT table_privs_are('public', 'contract_review_tokens', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'authenticated should have SELECT, INSERT, UPDATE on contract_review_tokens');
SELECT table_privs_are('public', 'contract_review_tokens', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on contract_review_tokens');

-- 2. telegram_binding_tokens
SELECT table_privs_are('public', 'telegram_binding_tokens', 'anon', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'anon should have SELECT, INSERT, UPDATE on telegram_binding_tokens');
SELECT table_privs_are('public', 'telegram_binding_tokens', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'authenticated should have SELECT, INSERT, UPDATE on telegram_binding_tokens');
SELECT table_privs_are('public', 'telegram_binding_tokens', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_binding_tokens');

-- 3. telegram_pending_links
-- anon access revoked by 20260804000001 (cross-tenant R/W hole; service_role/RPCs only).
SELECT table_privs_are('public', 'telegram_pending_links', 'anon', ARRAY[]::text[], 'anon should have NO privileges on telegram_pending_links (locked down 20260804000001)');
SELECT table_privs_are('public', 'telegram_pending_links', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'authenticated should have SELECT, INSERT, UPDATE on telegram_pending_links');
SELECT table_privs_are('public', 'telegram_pending_links', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on telegram_pending_links');

-- 4. justification_submission_tokens
SELECT table_privs_are('public', 'justification_submission_tokens', 'anon', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'anon should have SELECT, INSERT, UPDATE on justification_submission_tokens');
SELECT table_privs_are('public', 'justification_submission_tokens', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'authenticated should have SELECT, INSERT, UPDATE on justification_submission_tokens');
SELECT table_privs_are('public', 'justification_submission_tokens', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role should have ALL on justification_submission_tokens');

SELECT * FROM finish();
ROLLBACK;
