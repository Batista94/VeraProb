# Test Plan: 20260824000002_fix_applied_rejection_reason.sql

## Invariant Checks
- **INV-3 (Append-Only):** The migration does not alter ledger payloads, only fixes the extraction logic and queue backfill.
- **INV-DB (Zero-downtime):** Only `CREATE OR REPLACE FUNCTION` and a batched `UPDATE` with `LIMIT 1000`. No structural `ALTER TABLE` locks.

## Manual Testing
1. Dispute a sanction.
2. Accept the dispute. Verify the queue item's `rejection_reason` is set.
3. Dispute another sanction.
4. Overturn the dispute (Confirm Infraction) with a reason text.
5. Verify the queue item's `rejection_reason` is set correctly.
6. Verify past applied sanctions with no `rejection_reason` now have their reason backfilled from `sla_audit_ledger_v2`.
