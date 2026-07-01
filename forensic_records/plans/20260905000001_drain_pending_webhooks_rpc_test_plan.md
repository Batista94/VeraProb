# 20260905000001_drain_pending_webhooks_rpc Test Plan

## Objective
Verify the behavior of the `drain_pending_webhooks` RPC, which acts as the transactional claim mechanism for webhook dispatch.

## Invariants Covered
- **INV-22 (Tenant Isolation):** Ensures that cross-tenant webhooks cannot be claimed or drained together, and V5 verification skips misaligned configurations.
- **INV-3 (Append-Only/Immutability):** Delivery logs are not deleted, only their status is advanced.

## Test Cases

1. **Basic Claim and Status Transition**
   - **Setup:** Insert a `PENDING` webhook delivery log.
   - **Action:** Execute `drain_pending_webhooks(NULL, 10)`.
   - **Assertion:** Returns 1 row. Status transitions from `PENDING` to `DELIVERING`. `next_attempt_at` is set to exactly 2 minutes in the future (lease).

2. **V3 Key Status Enforcement (Revoked)**
   - **Setup:** Org has an active signing key, but its status is manually updated to `revoked`.
   - **Action:** Drain.
   - **Assertion:** Returns 0 rows. Log status transitions to `DEAD`. `last_error` is `KEY_REVOKED`. `system_audit_log` records a critical event.

3. **V3 Key Status Enforcement (Expired Retiring)**
   - **Setup:** Org signing key is `retiring` and `retiring_until` is in the past.
   - **Action:** Drain.
   - **Assertion:** Returns 0 rows. Log status transitions to `DEAD`. `last_error` is `KEY_EXPIRED`. `system_audit_log` records a critical event.

4. **V5 Org Cross-Check Leak Prevention**
   - **Setup:** `webhook_endpoints` record belongs to Org B, but `webhook_delivery_logs` belongs to Org A (simulating a DB constraint leak/bypass).
   - **Action:** Drain.
   - **Assertion:** The corrupt log is skipped. `system_audit_log` records a `CORRUPTION` event.

5. **Crash Recovery (Lease Reclamation)**
   - **Setup:** Insert a log with status `DELIVERING` and `next_attempt_at` in the past (expired lease). Insert another log with `DELIVERING` and `next_attempt_at` in the future (in-flight).
   - **Action:** Drain.
   - **Assertion:** Returns 1 row (the expired lease is reclaimed). The in-flight log remains untouched.

6. **LIMIT and Tenant Filtering**
   - **Setup:** Insert 5 logs for Org A, 5 logs for Org B.
   - **Action:** Drain for Org A with limit 2.
   - **Assertion:** Returns exactly 2 rows, all belonging to Org A.
