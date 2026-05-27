BEGIN;

-- Load pgTAP
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Plan assertions
SELECT plan(7);

-- ── T1: View exists ──────────────────────────────────────────────────────────
SELECT has_view('public', 'vw_device_heartbeat_status', 'vw_device_heartbeat_status view exists');

-- ── T2: View has security_invoker = true (INV-11) ────────────────────────────
SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'vw_device_heartbeat_status'
      AND c.reloptions::text LIKE '%security_invoker=true%'
  ),
  'vw_device_heartbeat_status must have security_invoker=true (INV-11)'
);

-- ── T3: View direct privileges ───────────────────────────────────────────────
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'anon', ARRAY[]::text[], 'anon has no privileges on vw_device_heartbeat_status');
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'authenticated', ARRAY[]::text[], 'authenticated has no privileges on vw_device_heartbeat_status');
SELECT table_privs_are('public', 'vw_device_heartbeat_status', 'service_role', ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 'service_role has SELECT and other privileges on vw_device_heartbeat_status');

-- ── T4: Dependent function exists ────────────────────────────────────────────
SELECT has_function('public', 'get_device_heartbeat_status', ARRAY['uuid'], 'get_device_heartbeat_status(uuid) function exists');

-- ── T5: Function execute privilege ───────────────────────────────────────────
SELECT ok(
  has_function_privilege('authenticated', 'get_device_heartbeat_status(uuid)', 'execute'),
  'authenticated role can execute get_device_heartbeat_status'
);

SELECT * FROM finish();
ROLLBACK;
