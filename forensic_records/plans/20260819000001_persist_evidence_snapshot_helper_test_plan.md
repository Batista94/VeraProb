# Test Plan: _persist_evidence_snapshot helper + approve_sanction snapshot sealing

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260819000001_persist_evidence_snapshot_helper.sql` | `20260819000001_persist_evidence_snapshot_test.sql` | ✅ |
| `20260819000002_forensic_evidence_by_queue.sql` | `20260819000001_persist_evidence_snapshot_test.sql` | ✅ |

## Intent

`approve_sanction` appended a `VERDICT_SEALED` ledger entry but never sealed a
forensic snapshot. `applied`-status cards in the Auditor Queue opened the Forensic
Evidence Modal, which tried to look up a snapshot by the verdict ledger id, found
nothing, and threw `ResourceNotFoundException` (modal 404). Root cause: the
snapshot build+persist body lived only in `seal_forensic_evidence` (detection path)
— the approval path had no equivalent.

Fix:
- `ADD COLUMN queue_entry_id UUID` on `forensic_evidence_snapshots` (nullable; write-
  once guaranteed by immutability trigger). Binds the snapshot to its originating
  queue entry so the UI can look it up by queue id rather than the verdict ledger id.
- Extract steps 5c–5h of `seal_forensic_evidence` (rule resolution → JCS hash →
  vault insert, minus the ledger append) into internal helper
  `_persist_evidence_snapshot(10 args)`. REVOKE ALL from external roles — internal
  use only by SECURITY DEFINER siblings running as the owner.
- `seal_forensic_evidence` refactored to append-ledger → call helper (behavior
  unchanged; EXCEPTION handler preserved for unique_violation race).
- `approve_sanction` terminal path extended: after `VERDICT_SEALED` ledger INSERT,
  call `_persist_evidence_snapshot(…, p_queue_entry_id, …)` with idempotency key
  `'approve:' || p_queue_entry_id`. Hard-fail (P0002) propagates if no active rule
  version — applied fine without sealed rule = chain-of-custody gap (INV-9/INV-21).
- Covering index `idx_fes_org_queue_entry` on `(organization_id, queue_entry_id,
  sealed_at_utc DESC) WHERE queue_entry_id IS NOT NULL`.
- `verify_forensic_evidence_by_queue(org_id, queue_entry_id)` SECURITY INVOKER
  (RLS-scoped): mirrors `verify_forensic_evidence` return shape; ORDER BY
  sealed_at_utc DESC LIMIT 1; P0002 if not found.

## Test Scenarios

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| T1 | Schema | `forensic_evidence_snapshots.queue_entry_id` column exists | INV-9 |
| T2 | Schema | `_persist_evidence_snapshot(10 args)` function exists | INV-9 |
| T3 | Schema | `verify_forensic_evidence_by_queue(2 args)` function exists | INV-26 |
| T4 | Security | `verify_forensic_evidence_by_queue` is SECURITY INVOKER | INV-22 |
| T5 | Grant | `authenticated` may EXECUTE `verify_forensic_evidence_by_queue` | INV-26 |
| T6 | Functional | `approve_sanction` completes without error for pending queue entry | INV-21 |
| T7 | Integrity | `forensic_evidence_snapshots.queue_entry_id` = queue entry id after approval | INV-21 |
| T8 | Integrity | `verify_forensic_evidence_by_queue` returns `authentic` for sealed entry | INV-9 |
| T9 | Error parity | Unknown `queue_entry_id` → P0002 (INV-26 404-parity) | INV-26 |

## Council Sign-off

- **Architect:** DRY extraction (single seal authority), `sealed_at_utc DESC` ordering ✅
- **Senior:** `PERFORM` idiom for discard, `FOR UPDATE` queue gate, idempotency key design ✅
- **QA/Security:** hard-fail P0002 on missing rule, REVOKE ALL on helper, grant posture ✅
- **Lead Reviewer:** Regression-ack comment in migration header ✅
