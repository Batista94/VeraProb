# Test Plan: 20260901000001_fix_dispute_retract_state_leak.sql

## Overview
This migration addresses a state leakage bug (Gap 1) during dispute retraction:
- When a dispute is retracted using `resolve_dispute` (with resolution `DISPUTE_RETRACTED`), the corresponding entry in the `sanction_review_queue` must transition back to the `pending` state.
- During this transition, all fields associated with active dispute tracking (`disputed_at`, `disputed_by`, `resolution_due_at`, `reviewed_at`, `rejection_reason`, etc.) must be cleared and set to `NULL` to prevent stale data leaks.

## Invariant Checks
- **INV-3 (Append-Only):** The transaction creates an append-only ledger log of type `DISPUTE_RETRACTED` in `public.sla_audit_ledger_v2`.
- **INV-6 (UTC Date):** Transitions are logged using the UTC timestamp provided in `p_occurred_at_utc`.
- **INV-22 (Tenant Isolation):** The retraction respects the `organization_id` filter and JWT claims.

## Verification Steps
1. Run `make test-db` to verify the execution.
2. In the corresponding pgTAP test, create a queue entry in `disputed` state with non-null values for `disputed_at`, `disputed_by`, `resolution_due_at`, `reviewed_at`, and `rejection_reason`.
3. Call `resolve_dispute` with `DISPUTE_RETRACTED` resolution.
4. Assert that the queue entry is reverted to `pending` and the state leak fields are nullified.
5. Verify that a ledger entry of type `DISPUTE_RETRACTED` is recorded.
