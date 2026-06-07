BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(1);

-- Verify table privileges for public.idempotency_keys on authenticated role
SELECT table_privs_are(
  'public',
  'idempotency_keys',
  'authenticated',
  ARRAY['SELECT', 'INSERT', 'UPDATE'],
  'authenticated has SELECT, INSERT, and UPDATE privileges on idempotency_keys'
);

SELECT * FROM finish();
ROLLBACK;
