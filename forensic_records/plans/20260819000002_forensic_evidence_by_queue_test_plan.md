# Test Plan: forensic_evidence_by_queue index + verify RPC

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260819000002_forensic_evidence_by_queue.sql` | `20260819000001_persist_evidence_snapshot_test.sql` | ✅ |

## Intent

Additive index and query RPC for the queue-entry lookup path introduced by
`20260819000001`. Without the index, the Forensic Evidence Modal query on
`(organization_id, queue_entry_id)` would be a full org-partition table scan.

- Partial index `idx_fes_org_queue_entry` on
  `(organization_id, queue_entry_id, sealed_at_utc DESC) WHERE queue_entry_id IS NOT NULL`.
- `verify_forensic_evidence_by_queue` SECURITY INVOKER, mirrors `verify_forensic_evidence`
  shape, raises P0002 for unknown entries (INV-26 404-parity).

Tests are covered in `20260819000001_persist_evidence_snapshot_test.sql` (T3–T5, T8–T9)
alongside the helper migration tests (same logical unit).
