# Test Plan: dispute_round_discriminator

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260823000001_dispute_round_discriminator.sql` | `20260823000001_dispute_round_discriminator_test.sql` | ✅ |

## Intent

The defense-in-depth unique index `uq_ledger_resolution_pN` was keyed
`(organization_id, payload->>'queue_entry_id')` over the resolution types
(`DISPUTE_ACCEPTED`, `DISPUTE_OVERTURNED`, `DISPUTE_RETRACTED`), permitting exactly
ONE resolution fact per queue entry forever. `DISPUTE_RETRACTED` is non-terminal
(returns the sanction to `pending`, re-disputable) yet consumed that single slot,
so a re-dispute followed by Confirmar/Anular collided → `23505`.

This migration adds `sanction_review_queue.dispute_round` (metadata-only,
`NOT NULL DEFAULT 0`) and swaps the per-partition partial unique indexes onto
`(organization_id, queue_entry_id, dispute_round)`. Each open→resolve cycle owns
an independent slot; same-cycle double-seal stays blocked.

## Test Scenarios

| # | Category | Scenario | Expected | INV |
|---|----------|----------|----------|-----|
| 1 | Schema | `dispute_round` column present | exists | — |
| 2 | Schema | column type | `integer` | INV-7 |
| 3 | Schema | nullability | `NOT NULL` | — |
| 4 | Schema | default | `0` | — |
| 5–6 | Index | legacy `uq_ledger_resolution_p0/p3` | dropped | INV-DB |
| 7–8 | Index | `uq_ledger_resolution_cycle_p0/p3` | present | INV-3 |
| 9 | Index | cycle index uniqueness | `indisunique` | INV-3 |
| 10 | Index | cycle index partiality | `indpred IS NOT NULL` | INV-3 |
| 11 | Index | cycle index keys on `dispute_round` | indexdef contains it | INV-3 |

## Council Sign-off

- **Architect:** discriminator preserves the agnostic ledger contract; cycle is a queue-entry property ✅
- **Senior:** add-column + DROP INDEX/CREATE INDEX is zero-downtime; NULL history rows are distinct in the unique index ✅
- **QA/Security:** no new disclosure surface; per-partition uniqueness globally sufficient (HASH key leads with org_id) ✅
- **Lead Reviewer:** `pr_scanner: ignore-regression` justified — additive discriminator, no merged migration modified ✅
