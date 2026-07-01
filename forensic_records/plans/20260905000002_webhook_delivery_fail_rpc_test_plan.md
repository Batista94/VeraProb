# 20260905000002_webhook_delivery_fail_rpc Test Plan

## Objective
Verify the backoff and retry mechanisms for failed webhook deliveries.

## Invariants Covered
- **INV-1 (Org Filter on every read/write):** `p_org_id` is part of the SELECT/UPDATE WHERE clause; a mismatched org cannot mutate another tenant's row.
- **INV-3 (Append-Only/Immutability):** Delivery logs are not deleted, only their status is advanced. Payload cannot be updated.

## Signature
`webhook_delivery_fail(p_log_id uuid, p_org_id uuid, p_error text)` — SECURITY DEFINER, GRANT EXECUTE to `service_role` only.

## Test Cases

1. **First Failure**
   - **Setup:** Insert a `DELIVERING` webhook delivery log.
   - **Action:** Execute `webhook_delivery_fail(log_id, org_id, 'HTTP_500')`.
   - **Assertion:** `status` is `FAILED`. `attempt_count` becomes 1. `next_attempt_at` is set approximately 30s in the future. `last_error` is 'HTTP_500'.

2. **Exhaustion (8th attempt)**
   - **Setup:** Insert a `DELIVERING` webhook delivery log with `attempt_count = 7`.
   - **Action:** Execute `webhook_delivery_fail(log_id, org_id, 'HTTP_500')`.
   - **Assertion:** `status` is `DEAD`. `next_attempt_at` is NULL.

3. **Tenant Isolation (INV-1)**
   - **Setup:** Insert a `DELIVERING` log for org C.
   - **Action:** Execute `webhook_delivery_fail(log_id, <other_org_id>, 'HTTP_500')`.
   - **Assertion:** Call is a silent no-op; the row's `status`/`attempt_count` are unchanged.
