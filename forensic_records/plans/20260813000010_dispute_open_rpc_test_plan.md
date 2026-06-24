# Test Plan: 20260813000010_dispute_open_rpc.sql

## Feature Overview
Adds the `dispute_sanction` SECURITY DEFINER RPC to transition a queue entry from `pending` to `disputed` atomically, calculating SLA deadlines in-line.

## Objectives
1. Verify the RPC correctly transitions `pending` items to `disputed`.
2. Verify the RPC calculates and sets `disputed_at`, `disputed_by`, and `resolution_due_at` on the queue entry.
3. Verify the RPC appends a `SANCTION_DISPUTED` ledger entry.
4. Verify the RPC enforces idempotency (fails if not pending).
5. Verify the RPC enforces tenant isolation (wrong org ID).

## Expected Outcomes
- The queue item state transitions atomically and cleanly.
- The `chk_srq_status` CHECK constraint is respected.
- The SLA `resolution_due_at` is populated correctly.
- All errors throw the correct Postgres error codes for UI mapping.
