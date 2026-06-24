# Test Plan: seal_snapshot_rejected_verdicts

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260824000001_seal_snapshot_rejected_verdicts.sql` | `20260824000001_seal_snapshot_rejected_verdicts_test.sql` | ✅ |

## Intent

`_persist_evidence_snapshot` (introduced in `20260819000001`) was wired only to
`approve_sanction`. Three RPCs that produce `rejected` queue entries never called
it, leaving `forensic_evidence_snapshots` without a row for those entries.
`verify_forensic_evidence_by_queue` then raised P0002 → `ResourceNotFoundException`
→ crash in "Cadeia de Custódia" and "Regra" tabs of `ForensicDossierModal`.

This migration patches the three affected RPCs via `CREATE OR REPLACE FUNCTION`
(zero-downtime, INV-DB) and adds `PERFORM _persist_evidence_snapshot(...)` in
each terminal verdict path:

| RPC | Terminal path | Ledger type sealed |
|-----|--------------|-------------------|
| `reject_sanction` | `VERDICT_REFUSED` | `VERDICT_REFUSED` |
| `resolve_dispute` | `DISPUTE_ACCEPTED` | `DISPUTE_ACCEPTED` |
| `confirm_peer_review` | REJECT / DISPUTE_ACCEPT | `VERDICT_REFUSED` / `DISPUTE_ACCEPTED` |

## Test Scenarios

| # | Category | Scenario | Expected | INV |
|---|----------|----------|----------|-----|
| T1 | Regression fix | `reject_sanction` seals forensic snapshot | `lives_ok` — no P0002 raised | INV-9, INV-21 |
| T2 | Regression fix | rejected entry verifies authentic | `verify_forensic_evidence_by_queue` → `status = 'authentic'` | INV-21 |
| T3 | Regression fix | `resolve_dispute` DISPUTE_ACCEPTED seals snapshot | `lives_ok` — no P0002 raised | INV-9, INV-21 |
| T4 | Regression fix | dispute-accepted entry verifies authentic | `verify_forensic_evidence_by_queue` → `status = 'authentic'` | INV-21 |
| T5 | Regression fix | `confirm_peer_review` REJECT seals snapshot | `lives_ok` — second auditor (different sub) confirms | INV-9, INV-21 |
| T6 | Regression fix | peer-reviewed rejected entry verifies authentic | `verify_forensic_evidence_by_queue` → `status = 'authentic'` | INV-21 |

## Companion fix: `20260813000008_refactor_rpcs_taxonomy_evidence_test.sql`

Tests T11–T13, T17–T18, T23–T25 in the existing taxonomy-evidence test also relied
on `reject_sanction` / `resolve_dispute` / `confirm_peer_review` paths that now call
`_persist_evidence_snapshot`. Those tests seeded contract `11111111-1111-1111-1111-1111111111c0`
without a matching `contract_rule_sets` row, causing P0002. A `contract_rule_sets` +
`contract_rule_versions` seed was added to that test file (no change to the migration
itself — append-only rule preserved).

## Council Sign-off

- **Architect:** additive `CREATE OR REPLACE` only; no column/table schema change; INV-9/INV-21 coverage extended to all terminal verdict paths ✅
- **Senior:** `p_resolved_by_user_id` (not null in terminal path) used for `resolve_dispute`; `v_user` used for `reject_sanction` and `confirm_peer_review` (both always set before terminal path); idempotency key used as `p_source_ref` ✅
- **QA-Security:** snapshot sealed atomically inside the RPC transaction; P0002 can only occur if `contract_rule_sets` is absent — now covered by test seeds; regression guard widget test added ✅
