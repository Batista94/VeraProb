# Test Plan: recycle_disputes_and_revoke_tokens

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260823000002_recycle_disputes_and_revoke_tokens.sql` | `20260823000002_recycle_disputes_and_revoke_tokens_test.sql` | ✅ |

## Intent

Completes the dispute-cycle discriminator and seals the Revogação de Acesso
Externo:

1. `dispute_sanction` increments `dispute_round` on each open.
2. `resolve_dispute` / `confirm_peer_review` embed `dispute_round` in the
   resolution payload (keys the cycle-scoped unique index).
3. Every internal verdict leaving the `disputed` lifecycle revokes the
   outstanding portal token (`revoked_at_utc` + `revoked_reason = 'VERDICT_SEALED'`)
   in the same transaction → phantom attachments blocked instantly.

Signatures are unchanged (`CREATE OR REPLACE`, no `DROP`) so committed pgTAP for
`resolve_dispute` / `reject_sanction` / `confirm_peer_review` / `approve_sanction`
/ `dispute_sanction` keeps passing.

## Test Scenarios

| # | Category | Scenario | Expected | INV |
|---|----------|----------|----------|-----|
| 1 | Recycle | E1 open dispute (round 1) | lives | INV-3 |
| 2 | Recycle | E1 retract (round-1 RETRACTED) | lives | INV-3 |
| 3 | Recycle | E1 re-open (round 2) | lives | INV-3 |
| 4 | **Regression** | E1 round-2 ACCEPTED after round-1 RETRACTED | lives (no 23505) | INV-3 |
| 5 | State | E1 terminal status | `rejected` | — |
| 6 | State | E1 `dispute_round` | `2` | — |
| 7 | Ledger | round-1 RETRACTED fact | exactly 1 | INV-3 |
| 8 | Ledger | round-2 ACCEPTED fact | exactly 1 | INV-3 |
| 9 | Revoke | E1 portal token revoked on verdict | `revoked_at_utc` set | INV-1/INV-22 |
| 10 | Revoke | revocation reason | `VERDICT_SEALED` | — |
| 11 | Defense-in-depth | same-cycle (round 2) duplicate ACCEPTED | `23505` | INV-3 |
| 12–13 | Recycle | E2 open → retract | lives | INV-3 |
| 14 | **Regression** | E2 re-open → OVERTURNED (seals snapshot) | lives (no 23505) | INV-21 |
| 15 | State | E2 terminal status | `applied` | — |

### No-false-positive guard

Scenario 11's manual duplicate embeds the SAME `dispute_round` (2) the RPC wrote,
so it genuinely collides on the cycle index rather than passing on a distinct key.

## Council Sign-off

- **Architect:** dual-control fork preserved verbatim; revocation is a side-effect of the terminal transition, not a new lifecycle ✅
- **Senior:** `CREATE OR REPLACE` based on each LATEST definition; `≤1` active token per entry (partial unique) → single-row revoke ✅
- **QA/Security:** revocation re-asserts org+entry scope; `revoked_at_utc` write-once trigger intact; no oracle introduced ✅
- **Lead Reviewer:** `pr_scanner: ignore-regression` justified — additive `CREATE OR REPLACE`, signatures unchanged ✅
