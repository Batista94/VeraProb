# Test Plan: 20260816000005_fix_test_helpers_grants_regression.sql

This migration ensures that `test_cleanup_forensic_data` and `test_tamper_raw_telemetry_payload` are NOT executable by `authenticated` or `anon` roles, fixing the test failures in `20260815000001_restore_execute_grants_revoke_regression_test.sql`.

No additional pgTAP test needed as this makes the existing failing tests (A3 and A3b) pass.
