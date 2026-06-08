BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- 1 table * 3 roles + 3 client functions * 2 roles + 1 cleanup function * 3 roles = 12 assertions
SELECT plan(12);

-- ── 1. Table grants for public.idempotency_keys ──────────────────────────────
-- Note: A later migration (20260717000005) revokes all access from authenticated/anon,
-- so in the final migrated state they should have no privileges.
SELECT table_privs_are('public', 'idempotency_keys', 'anon', ARRAY[]::text[], 'anon has no privileges on idempotency_keys');
SELECT table_privs_are('public', 'idempotency_keys', 'authenticated', ARRAY['SELECT', 'INSERT', 'UPDATE'], 'authenticated has SELECT, INSERT, and UPDATE privileges on idempotency_keys in final schema');
SELECT table_privs_are('public', 'idempotency_keys', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has ALL on idempotency_keys');

-- ── 2. Function grants ───────────────────────────────────────────────────────
-- try_acquire_idempotency_key
SELECT function_privs_are('public', 'try_acquire_idempotency_key',
  ARRAY['text', 'text', 'text', 'uuid', 'integer'], 'authenticated', ARRAY['EXECUTE'],
  'authenticated has EXECUTE on try_acquire_idempotency_key');
SELECT function_privs_are('public', 'try_acquire_idempotency_key',
  ARRAY['text', 'text', 'text', 'uuid', 'integer'], 'service_role', ARRAY['EXECUTE'],
  'service_role has EXECUTE on try_acquire_idempotency_key');

-- complete_idempotency_key
SELECT function_privs_are('public', 'complete_idempotency_key',
  ARRAY['text', 'text', 'integer', 'jsonb'], 'authenticated', ARRAY['EXECUTE'],
  'authenticated has EXECUTE on complete_idempotency_key');
SELECT function_privs_are('public', 'complete_idempotency_key',
  ARRAY['text', 'text', 'integer', 'jsonb'], 'service_role', ARRAY['EXECUTE'],
  'service_role has EXECUTE on complete_idempotency_key');

-- fail_idempotency_key
SELECT function_privs_are('public', 'fail_idempotency_key',
  ARRAY['text', 'text', 'integer', 'jsonb'], 'authenticated', ARRAY['EXECUTE'],
  'fail_idempotency_key is executable by authenticated');
SELECT function_privs_are('public', 'fail_idempotency_key',
  ARRAY['text', 'text', 'integer', 'jsonb'], 'service_role', ARRAY['EXECUTE'],
  'fail_idempotency_key is executable by service_role');

-- cleanup_expired_idempotency
-- Note: 20260717000002 revokes execute on cleanup_expired_idempotency from PUBLIC and anon,
-- but authenticated retains its default execute permission.
SELECT function_privs_are('public', 'cleanup_expired_idempotency',
  ARRAY['integer'], 'service_role', ARRAY['EXECUTE'],
  'service_role has EXECUTE on cleanup_expired_idempotency');
SELECT function_privs_are('public', 'cleanup_expired_idempotency',
  ARRAY['integer'], 'authenticated', ARRAY['EXECUTE'],
  'authenticated has EXECUTE on cleanup_expired_idempotency in final schema');
SELECT function_privs_are('public', 'cleanup_expired_idempotency',
  ARRAY['integer'], 'anon', ARRAY[]::text[],
  'anon has NO privileges on cleanup_expired_idempotency');

SELECT * FROM finish();
ROLLBACK;
