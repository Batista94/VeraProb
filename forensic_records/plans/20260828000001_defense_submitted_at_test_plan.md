# Test Plan: defense_submitted_at (Auditor queue — false tab signal fix — PKG1)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260828000001_defense_submitted_at.sql` | `20260828000001_defense_submitted_at_test.sql` | ✅ |

## Intent

After a carrier submits its contestation through the portal, the queue correctly
stays `disputed` (per `20260827000001` — a status flip mints a zombie). But the
card then sits under the "Aguardando Evidência" tab forever, a false signal: the
evidence has already arrived; the AUDITOR's verdict is what is pending.

This migration adds a denormalized **write-once** `defense_submitted_at`
timestamp on `sanction_review_queue`, set the instant the carrier submits (file
OR text). The realtime stream is keyed on the queue row, so writing the column
fires a client update; the UI re-labels the card "DEFESA RECEBIDA" and sorts it
to the top WITHOUT any status flip. The column is sealed write-once by
`prevent_srq_immutable_mutation` to close an anti-forensic exploit (an auditor
clearing the flag to re-hide a received defense and issue a "no defense"
verdict).

Both portal RPCs are rebased on their **latest** defs (`20260827000001`); the
only deltas are `FOR SHARE → FOR UPDATE` on the queue lock and the
`defense_submitted_at` stamp (IS NULL guard → first submission wins, idempotent).
Queue status semantics are byte-identical (stays `disputed`).

## Anti-regression guards

- **R1 (no-flip preserved):** REGISTER_KEEPS_DISPUTED / JUSTIFY_KEEPS_DISPUTED
  re-assert the queue stays `disputed` — FAIL the instant anyone re-introduces a
  flip while editing these RPCs.
- **R2 (replay idempotency):** REGISTER_REPLAY_NO_ADVANCE proves a second
  finalize does NOT advance `defense_submitted_at` (the IS NULL guard holds), so
  the forensic "first submission" instant is stable.
- **R3 (write-once seal):** WRITE_ONCE_BLOCKS proves a direct UPDATE that clears
  or changes a set `defense_submitted_at` is rejected (`restrict_violation`).
- The committed `20260827000001_*_test.sql` continues to assert ST1–ALERT* and
  is unaffected (this migration changes neither status nor alert behavior).

## Test Scenarios — `20260828000001_*_test.sql` (8 assertions)

| # | Category | Assertion | INV |
|---|----------|-----------|-----|
| COL_EXISTS | Schema | `sanction_review_queue.defense_submitted_at` exists, type `timestamp with time zone` | INV-6 |
| COL_NULLABLE | Schema | column is nullable with NO column default | INV-6 |
| REGISTER_SETS | Behavior | `register_portal_evidence` sets `defense_submitted_at` (non-null) | INV-18 |
| REGISTER_KEEPS_DISPUTED | Integrity | queue still `disputed` after register (anti-regression) | INV-3 |
| REGISTER_REPLAY_NO_ADVANCE | Idempotency | register replay leaves `defense_submitted_at` unchanged (IS NULL guard) | INV-9 |
| JUSTIFY_SETS | Behavior | `submit_portal_justification_only` sets `defense_submitted_at` | INV-18 |
| JUSTIFY_KEEPS_DISPUTED | Integrity | queue still `disputed` after justification submit | INV-3 |
| WRITE_ONCE_BLOCKS | Integrity | UPDATE clearing/altering a set `defense_submitted_at` throws `restrict_violation` | INV-18 |

## Council Sign-off

- Architect ✅ — Denormalized UX signal on the queue row; no status-machine change; carrier submission still "evidence, not peer-review proposal".
- Senior ✅ — Additive `CREATE OR REPLACE` rebased on LATEST defs; only deltas are `FOR UPDATE` + idempotent stamp; metadata-only `ALTER ADD COLUMN` (zero-downtime).
- QA-Security ✅ — Write-once trigger seal (INV-18); org scoping preserved inside SECURITY DEFINER; no DEFAULT (server-derived); no merged migration edited.
- Lead Reviewer ✅ — `pr_scanner: ignore-regression` justified (additive); 1:1 plan present; anti-regression R1–R3 close the gap.

## Run Command

```bash
make test-db
```
