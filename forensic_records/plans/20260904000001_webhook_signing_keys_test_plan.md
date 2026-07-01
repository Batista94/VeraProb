# Test Plan: Webhook Signing Keys (20260904000001)

## Objective
Verify the creation of `webhook_signing_keys`, including RLS restrictions, EXCLUDE constraint, and proper `user_role` mapping.

## Verification Steps
1. Insert two `active` keys for the same `organization_id` -> MUST RAISE EXCEPTION (Exclusion constraint).
2. Insert one `active` and one `retiring` -> MUST PASS.
3. As non-admin authenticated -> MUST FAIL to insert/update.
4. As admin authenticated of same org -> MUST PASS.
5. As admin of different org -> MUST FAIL.
