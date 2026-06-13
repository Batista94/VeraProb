BEGIN;

SELECT plan(1);

-- INV-2: Ensure that authenticated role cannot execute test_cleanup_forensic_data
SELECT function_privs_are(
  'public',
  'test_cleanup_forensic_data',
  ARRAY['uuid'],
  'authenticated',
  ARRAY[]::text[],
  'authenticated role should NOT have EXECUTE on test_cleanup_forensic_data'
);

SELECT * FROM finish();

ROLLBACK;
