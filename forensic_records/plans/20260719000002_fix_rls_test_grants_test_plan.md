# Test Plan: 20260719000002_fix_rls_test_grants

## Objective
Verify that `execution_state_transitions` and `spoofing_audit_entries` have `SELECT` and `INSERT` grants for the `authenticated` role to support client-facing repository operations and OCC visibility, while keeping them revoked for `anon`.

## Tables to verify:
* public.execution_state_transitions
* public.spoofing_audit_entries

## Test Steps
1. Execute integration tests to confirm client-facing querying/inserting works under the `authenticated` role context.
2. Confirm `authenticated` has SELECT and INSERT privileges on both tables.
3. Confirm RLS continues to isolate rows for `authenticated` users on both tables.
4. Confirm `anon` has NO privileges on these tables.
