# Test Plan: 20260901000006_fix_rpc_jwt_org_claim.sql

## Objective
Verify that `resolve_dispute`, `reject_sanction`, and `approve_sanction` successfully authenticate and authorize tenant users based on the top-level `organization_id` JWT claim instead of the nested `app_metadata` path. Also verify that data masking in `read_infraction_context` behaves correctly.

## Invariants Targeted
- **INV-1 (Org Filtering)**: Ensure tenant users are correctly restricted to their own organization's records.
- **INV-2 (JWT Claims)**: RLS/JWT claims validation uses `auth.jwt() ->> 'organization_id'` to isolate tenants.
- **INV-22 (Tenant Isolation)**: Cross-tenant operations must be strictly rejected.

## Pre-requisites
- Migration `20260901000006_fix_rpc_jwt_org_claim.sql` must be applied successfully.

## Test Strategy (pgTAP)
1. **JWT claim authorization**:
   - Set request JWT claim using `organization_id` at the top level (e.g. `{"role":"authenticated","sub":"...","organization_id":"...","app_metadata":{"role":"AUDITOR"}}`).
   - Call `resolve_dispute`, `reject_sanction`, and `approve_sanction` and verify that they execute successfully without raising authentication/authorization exceptions when the org matches.
   - Verify that they raise an exception when the JWT org claim does not match the parameter `p_organization_id` or when the user doesn't have the appropriate auditor role.
2. **Grants**:
   - Ensure the required permissions are granted to `authenticated` and revoked from `public`.

## Execution
Run `make test-db` to validate all these behaviors via the test suite.

## Expected Outcomes
- All tests in `20260901000006_fix_rpc_jwt_org_claim_test.sql` pass successfully.
- Proper tenant boundary enforcement is maintained via the top-level `organization_id` JWT claim.
