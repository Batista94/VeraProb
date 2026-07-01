# Test Plan: Webhook Endpoints (20260904000002)

## Objective
Verify the creation of `webhook_endpoints`, HTTPs constraint, and proper `user_role` RLS mapping.

## Verification Steps
1. Insert URL starting with `http://` -> MUST RAISE EXCEPTION (Check constraint).
2. Insert URL starting with `https://` -> MUST PASS.
3. As non-admin authenticated -> MUST FAIL to insert/update.
4. As admin authenticated of same org -> MUST PASS.
5. As admin of different org -> MUST FAIL.
