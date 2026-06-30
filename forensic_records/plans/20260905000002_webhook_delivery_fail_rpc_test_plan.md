# 20260905000002_webhook_delivery_fail_rpc Test Plan

## Objective
Verify the backoff and retry mechanisms for failed webhook deliveries.

## Invariants Covered
- **INV-3 (Append-Only/Immutability):** Delivery logs are not deleted, only their status is advanced. Payload cannot be updated.

## Test Cases

1. **First Failure**
   - **Setup:** Insert a `DELIVERING` webhook delivery log.
   - **Action:** Execute `webhook_delivery_fail(log_id, 'HTTP_500')`.
   - **Assertion:** `status` is `FAILED`. `attempt_count` becomes 1. `next_attempt_at` is set approximately 30s in the future. `last_error` is 'HTTP_500'.

2. **Exhaustion (8th attempt)**
   - **Setup:** Insert a `DELIVERING` webhook delivery log with `attempt_count = 7`.
   - **Action:** Execute `webhook_delivery_fail(log_id, 'HTTP_500')`.
   - **Assertion:** `status` is `DEAD`. `next_attempt_at` is NULL.

3. **Immutability Enforcement**
   - **Setup:** Attempt to update the `payload` or `organization_id` of the log while calling `webhook_delivery_fail`.
   - **Assertion:** The DB trigger raises a `restrict_violation`.
