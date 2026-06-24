# Test Plan: 20260901000002_enforce_nowait_concurrency_lock.sql

## Overview
This migration enforces a Fail-Fast pessimistic concurrency lock (Gap 2) on audit review functions:
- Applies `FOR UPDATE NOWAIT` when retrieving a queue entry in `resolve_dispute`, `approve_sanction`, and `reject_sanction`.
- Prevents concurrent transactions from blocking or causing deadlocks. If a row is already locked by another transaction, Postgres throws a lock contention error immediately instead of waiting.

## Invariant Checks
- **INV-3 (Append-Only):** The locks do not bypass the ledger; operations still record append-only logs if they acquire the lock.
- **INV-DB (Zero-downtime):** Replaces existing functions without schema modification or column drops.

## Verification Steps
1. In the corresponding pgTAP test, open a transaction and lock a queue entry using `SELECT * FROM sanction_review_queue WHERE id = ... FOR UPDATE`.
2. Open a nested autonomous transaction or a concurrent block, and attempt to call `resolve_dispute`, `approve_sanction`, or `reject_sanction` on that same queue entry.
3. Assert that the call fails immediately with code `55P03` (lock_not_available), proving that the `NOWAIT` modifier is working as intended.
