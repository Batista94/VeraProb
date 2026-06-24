# Test Plan: 20260901000004_fix_db_test_regressions.sql

## Objective
Restore correct signatures for dual-control RPCs that were overwritten by a legacy branch in `20260901000002_enforce_nowait_concurrency_lock.sql`, while retaining the `FOR UPDATE NOWAIT` functionality. Also fix aggressive data masking in `read_infraction_context` that broke test suite execution.

## Invariants Targeted
- **INV-22 (Data Masking)**: Data masking must protect data in unauthorized states but MUST NOT block legitimate access for `pending`, `applied`, or `disputed` status.
- **INV-3 / INV-26**: Ensure all forensic logs are recorded correctly via dual-control without being blocked by ambiguous function signatures.

## Pre-requisites
- Migration `20260901000004_fix_db_test_regressions.sql` must be applied successfully.

## Test Strategy (pgTAP)

1. **Verify Signatures:**
   - Ensure `approve_sanction` now accepts exactly 7 arguments.
   - Ensure `resolve_dispute` now accepts exactly 9 arguments.
   - Ensure `reject_sanction` now accepts exactly 7 arguments.
   - Test suites (e.g. `20260812000003_dual_control_rpcs_test.sql`) should execute without `42725 function ... is not unique` errors.

2. **Verify Data Masking:**
   - Execute `read_infraction_context` tests using a test token.
   - Ensure the context returns unmasked data for a `pending` sanction (which is used heavily in DB testing).
   - Ensure the context returns unmasked data for an `applied` sanction (when a carrier decides to dispute).
   - Ensure the context returns unmasked data for a `disputed` sanction (active dispute state).
   - Ensure the context returns strictly MASKED (NULL) data for a `rejected` sanction.

3. **Verify Concurrency Locks:**
   - The test `20260901000002_enforce_nowait_concurrency_lock_test.sql` must pass, proving that concurrent executions of `approve_sanction` instantly raise `55P03` (lock_not_available) rather than queueing.

## Execution
Run `make test-db` to validate all these behaviors via existing test suites.

## Expected Outcomes
- All existing pgTAP tests must now PASS.
- No `function is not unique` errors.
- No `NULL` test assertions for `read_infraction_context` when dealing with valid pre-terminal statuses.
