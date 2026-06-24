# Test Plan: portal_no_status_flip_and_alert (Dispute Portal → Tribunal fix — PKG1)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260827000001_portal_no_status_flip_and_alert.sql` | `20260827000001_portal_no_status_flip_and_alert_test.sql` | ✅ |
| `20260820000002_portal_state_transition.sql` (stub replaced) | `20260820000002_portal_state_transition_test.sql` | ✅ |

## Intent

The portal submission RPCs (`register_portal_evidence`,
`submit_portal_justification_only`) illegally flipped
`sanction_review_queue.status` from `disputed` → `pending_peer_review` on a
**carrier** submission, without setting `peer_review_proposed_action` /
`peer_review_expires_at`. That ejected the card from the "Aguardando Evidência"
stream (which filters `status='disputed'`) and produced a **zombie**:
`confirm_peer_review` fell into the `ELSE`→42501 (un-confirmable) and
`expire_stale_peer_reviews` skipped it (`WHERE peer_review_expires_at IS NOT
NULL`). The dispute became irresolvible and the evidence unreachable
("aparece em pendentes e depois some"). The RPCs also never wrote
`operational_alerts`, so the operator was never notified in the triage drawer.

This migration removes the illegal flip (the queue **stays disputed**, the card
holds in "Aguardando Evidência"), keeps the one-shot token revocation as the
anti-double-submit guard, and emits a `DISPUTE_DEFENSE_SUBMITTED`
`operational_alert` (**metadata only** — the raw testimony never leaves the
sealed submission row; the ledger stays hash-only, INV-3/9). The
`valid_alert_type` CHECK is widened zero-downtime (ADD NOT VALID → VALIDATE →
DROP → RENAME back to the canonical name so committed tests keep passing).

The legitimate `disputed → pending_peer_review` transition (auditor dual-control
via `resolve_dispute` / approve-reject RPCs, which DO set the peer-review fields)
is untouched. `audit_portal_submission` never required the flip (it only checks
the submission is `PENDING_AUDIT`), so accepting/rejecting a portal tile is
unaffected.

## Why the suite previously went green (false positive eliminated)

`20260820000002_portal_state_transition_test.sql` was a lazy `SELECT pass()`
stub (CI Block #14). The committed `20260817000005` / `20260818000005` tests
assert `portal_evidence_submissions.status='PENDING_AUDIT'` (the *submission*
table) and never `sanction_review_queue.status` — so the illegal queue flip was
never observed. ST1/ST2 below close that gap and will FAIL the instant the flip
is re-introduced.

## Test Scenarios

### `20260827000001_*_test.sql` (14 assertions)

| # | Category | Assertion | INV |
|---|----------|-----------|-----|
| ST1 | Integrity | queue stays `disputed` after `register_portal_evidence` (anti-regression) | INV-3 |
| ST2 | Integrity | queue stays `disputed` after `submit_portal_justification_only` | INV-3 |
| ST3 | Token | file token revoked after finalize (one-shot guard) | INV-18 |
| TOKEN-TEXT | Token | text token revoked after submit | INV-18 |
| ST4 | Idempotency | register replay returns the same attachment | INV-9 |
| ALERT1 | Notification | exactly one `DISPUTE_DEFENSE_SUBMITTED` alert for the file queue | INV-1 |
| ALERT1b | Notification | file alert context is metadata-only (no `justification_text`); right plate/driver/fine/filename/severity/org | INV-1/3/9 |
| ALERT3 | Idempotency | register replay does not duplicate the alert (`ON CONFLICT` + early return) | INV-9 |
| ALERT2 | Notification | exactly one alert for the text queue | INV-1 |
| ALERT2b | Notification | text alert `defense_type=text`, null filename, right fine | INV-1 |
| ZOMBIE | Integrity | zero `pending_peer_review` rows for the org (portal never mints one) | INV-3 |
| CHK-CANON | Schema | constraint keeps canonical name `valid_alert_type` after rename-back | INV-DB |
| CHK7 | Schema | `DISPUTE_DEFENSE_SUBMITTED` admitted by the widened CHECK | INV-DB |
| CHK-REJECT | Schema | an unknown `alert_type` is still rejected (CHECK active) | INV-DB |

### `20260820000002_*_test.sql` (2 assertions — stub replaced)

| # | Category | Assertion | INV |
|---|----------|-----------|-----|
| 1 | Integrity | queue stays `disputed` after portal finalize (no illegal flip) | INV-3 |
| 2 | Token | one-shot token revoked after portal finalize | INV-18 |

## Council Sign-off

- Architect ✅ — Restores the state machine: a carrier submission is evidence, not a peer-review proposal; the legitimate dual-control flip is untouched.
- Senior ✅ — Additive `CREATE OR REPLACE` rebased on the LATEST defs; zero-downtime CHECK widen with rename-back; `RETURNING id` captures the ledger fact for the alert.
- QA-Security ✅ — Alert is metadata-only (INV-3/9); org-scoped write; idempotent via `unique_alert_per_event`; token revocation preserved (INV-18). No merged migration edited.
- Lead Reviewer ✅ — `pr_scanner: ignore-regression` justified (additive RPC fix removing an illegal transition); 1:1 plan present; false-green stub eliminated (CI Block #14).

## Run Command

```bash
make test-db
```
