# Test Plan: 20260822000004_portal_delete_triggers_honor_test_cleanup_guc.sql

**Governing Migration:** `supabase/migrations/20260822000004_portal_delete_triggers_honor_test_cleanup_guc.sql`
**Companion pgTAP:** `supabase/tests/20260822000004_portal_delete_triggers_honor_test_cleanup_guc_test.sql`
**Invariants Checked:** INV-1, INV-3, INV-22

## Problem Fixed

`20260822000003` reordered `test_cleanup_forensic_data` to delete the dispute-portal
FK-child tables before `sanction_review_queue`. But the six append-only `BEFORE DELETE`
triggers guarding those tables RAISE unconditionally — none checked the maintenance GUC
the cleanup RPC sets (`SET LOCAL vera.authorized_test_cleanup = 'on'`). The first child
DELETE with a live row therefore threw `restrict_violation` (`prevent_dpt_delete` line 3),
so `tearDownAll` cleanup failed and `sanction_review_queue` was never emptied.

**Triggers fixed (now mirror the canonical `prevent_tel_delete` pattern from
`20260423180000_forensic_test_hardening` — `RETURN OLD` when the GUC is set, else block):**
`prevent_dpt_delete`, `prevent_dea_delete`, `prevent_sack_delete`,
`prevent_pes_delete`, `prevent_pjs_delete`, `prevent_sel_delete`.

Production paths never set the GUC, so append-only immutability (INV-3) is preserved;
only the service_role test-cleanup RPC (whose transaction sets the GUC) can delete.

## Scenarios

1. **T1: Cleanup completes with a live row in every portal table**
   - Condition: One row seeded in each of the six append-only FK-child tables
     (`dispute_portal_tokens`, `dispute_evidence_attachments`,
     `portal_evidence_submissions`, `portal_justification_submissions`,
     `sanction_acknowledgements`, `sanction_escalation_log`) + parent queue row.
   - Expected: `test_cleanup_forensic_data(org_id)` completes without
     `restrict_violation` (`lives_ok`) — all six triggers honor the GUC.

2. **T2: sanction_review_queue emptied after call**
   - Condition: Same seeded org, immediately after the call.
   - Expected: `COUNT(*) = 0` for org in `sanction_review_queue`.

3. **T3: All dispute-portal FK children emptied after call**
   - Condition: Same seeded org, immediately after the call.
   - Expected: Combined `COUNT(*) = 0` across all six child tables for the org.

## Go/No-Go Gate

All three assertions must PASS before merge to main. The companion test for
`20260822000003` (4 assertions) must also remain green.
