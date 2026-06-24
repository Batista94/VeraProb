# Test Plan: 20260824000002_fix_applied_rejection_reason.sql

## Overview
This migration fixes a critical data retention and UI-crashing bug:
1. `resolve_dispute` and `confirm_peer_review` were discarding `p_resolution_reason` from `sanction_review_queue` when the verdict was `DISPUTE_OVERTURNED` (applied).
2. `seal_dispute_resolution_snapshot` was not recording `queue_entry_id` to `forensic_evidence_snapshots`, breaking the `ResourceNotFoundException` UI modal for applied cards.

## Invariant Checks
- **INV-3 (Append-Only):** The migration does not alter ledger payloads, only fixes the extraction logic, vault metadata linkage, and queue backfill.
- **INV-DB (Zero-downtime):** Uses `CREATE OR REPLACE FUNCTION` and backfills via batched `DO` block loops. The `seal_dispute_resolution_snapshot` is safely dropped and recreated within the same migration transaction.
- **INV-9 (SHA-256 seal):** Signature unchanged, hashing mechanism untouched. Just passes through `queue_entry_id` to the vault row.
- **INV-21 (Verdict linkage):** Explicitly restoring the queue-to-snapshot mapping so the UI can retrieve the dossier.

## Verification Steps
1. Make sure `make test-db` passes.
2. Check that confirming an infraction with a justification text now sets `rejection_reason` on `sanction_review_queue`.
3. Check that the UI's forensic modal ("dossiê") opens successfully for a card that was disputed and then the fine was applied (`DISPUTE_OVERTURNED`).
