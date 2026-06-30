# Test Plan: Webhook Delivery Logs (20260904000003)

## Objective
Verify the creation of `webhook_delivery_logs`, its idempotency unique constraint, RLS, and strict immutability trigger.

## Verification Steps
1. Insert two rows with the same `(organization_id, ledger_entry_id, endpoint_id, event_type)` -> MUST RAISE EXCEPTION (Idempotency unique constraint).
2. Update `payload` -> MUST RAISE EXCEPTION (Immutability guard).
3. Update `signing_key_id` from NULL to UUID -> MUST PASS (One-shot).
4. Update `signing_key_id` from UUID to another UUID -> MUST RAISE EXCEPTION (One-shot guard).
5. DELETE row -> MUST RAISE EXCEPTION.
