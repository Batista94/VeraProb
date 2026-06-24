# Test Plan: 20260822000003_fix_test_cleanup_fk_order.sql

**Governing Migration:** `supabase/migrations/20260822000003_fix_test_cleanup_fk_order.sql`
**Companion pgTAP:** `supabase/tests/20260822000003_fix_test_cleanup_fk_order_test.sql`
**Invariants Checked:** INV-2, INV-22

## Problem Fixed

`test_cleanup_forensic_data` RPC (first defined in `20260820000005`) deleted
`sanction_review_queue` before its FK-child tables added by the Phase 10.6 dispute
portal migrations (`20260813`–`20260818`). This caused a `23503 FK violation` in
every `tearDownAll` that exercised the cleanup RPC, leaving stale rows that then
triggered `23505` collisions in subsequent test runs.

**FK dependency order (leaf → root):**
`dispute_evidence_attachments` → `portal_justification_submissions` →
`sanction_acknowledgements` → `portal_evidence_submissions` →
`dispute_portal_tokens` → `sanction_escalation_log` → `sanction_review_queue`

## Scenarios

1. **T1: Function exists**
   - Condition: Migration applied.
   - Expected: `has_function('public', 'test_cleanup_forensic_data', ['uuid'])` passes.

2. **T2: Grant hardening — authenticated cannot execute**
   - Condition: `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO service_role`.
   - Expected: `has_function_privilege('authenticated', ..., 'execute')` = false.

3. **T3: FK deletion order — no 23503 when dispute_portal_tokens child exists**
   - Condition: `sanction_review_queue` row + `dispute_portal_tokens` FK-child exist for same org.
   - Expected: `test_cleanup_forensic_data(org_id)` completes without error (`lives_ok`).

4. **T4: sanction_review_queue emptied after function call**
   - Condition: Same seeded org as T3, immediately after call.
   - Expected: `COUNT(*) = 0` for org in `sanction_review_queue`.

## Go/No-Go Gate

All four assertions must PASS before merge to main.
