# Test Plan: Revoke Audit Portal Submission RPC

**Migration**: `20260828000002_revoke_audit_portal_submission.sql`

## Background & Context
The "Snazzy Storm" process removes the per-file accept/reject buttons for portal submissions in the auditor queue, streamlining evidence into a read-only zone that the auditor views before issuing a final verdict on the entire dispute. Thus, the `audit_portal_submission` RPC is obsolete and must be dropped.

## Hypothesis
- Dropping `audit_portal_submission` succeeds and removes the function from the database.
- Other portal functions (`list_portal_submissions`) remain unaffected and return correctly.
- INV-DB: Zero-downtime rules are respected as UI code using the RPC has been removed.

## Setup & Scenarios

1. **Verify RPC Absence:** Verify that `audit_portal_submission` does not exist in the `public` schema.

## Verification Steps
- `make test-db` to run the pgTAP tests. The test should query `pg_proc` to assert that the function no longer exists.
