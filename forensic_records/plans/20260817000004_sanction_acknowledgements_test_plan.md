# Test Plan: sanction_acknowledgements (Sprint A M4 — De Acordo)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260817000004_sanction_acknowledgements.sql` | `20260817000004_sanction_acknowledgements_test.sql` | ✅ |

## Intent

Forensic record of a carrier formally accepting a penalty ("De Acordo"). Triple
signal: this table (detail + hash binding) + `sanction_review_queue.status =
'acknowledged'` (terminal AR index) + ledger fact `SANCTION_ACKNOWLEDGED` (M5).
PORTAL_TOKEN acknowledgements are hash-bound (carrier can only accept the served
snapshot); INTERNAL_RECORD captures off-band acceptance by a TENANT_ADMIN with
no hash. No UNIQUE on `queue_entry_id` (overturn→re-applied→re-ack cycles legal).

Widens `chk_srq_status` to admit `acknowledged` via the H1 zero-downtime swap
(canonical name preserved), and seals `acknowledged` as **terminal** in
`prevent_srq_immutable_mutation` (debt conceded — no retract, no re-dispute).

## Test Scenarios (15 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| S1 | Structure | table exists | `has_table` | - |
| S2 | Structure | `snapshot_hash_acknowledged` column exists | `has_column` | INV-9 |
| S3 | Structure | `chk_srq_status` admits `acknowledged` | `LIKE` | - |
| C1 | Constraint | PORTAL_TOKEN w/o hash rejected | `throws 23514` | INV-9 |
| C2 | Constraint | INTERNAL_RECORD w/o user rejected | `throws 23514` | - |
| C3 | Constraint | invalid method rejected | `throws 23514` | - |
| C4 | Constraint | malformed snapshot hash rejected | `throws 23514` | INV-9 |
| HP1 | Happy | valid PORTAL_TOKEN ack inserts | `lives_ok` | - |
| HP2 | Happy | valid INTERNAL_RECORD ack inserts | `lives_ok` | - |
| IM | Append-only | UPDATE blocked | `throws 23001` | INV-3 |
| DEL | Append-only | DELETE blocked | `throws 23001` | INV-3 |
| G1 | Grant | authenticated can SELECT | `has_table_privilege` | INV-2 |
| G2 | Grant | authenticated cannot INSERT (RPC-only) | `NOT has_table_privilege` | INV-DATA-API-GRANT |
| TS1 | Lifecycle | applied → acknowledged allowed | `lives_ok` | - |
| TS2 | Lifecycle | acknowledged is terminal | `throws 23001` | INV-3 |

## Council Sign-off

- Architect ✅ — Triple-signal acknowledgement; no UNIQUE allows legal re-ack cycles.
- Senior ✅ — H1 canonical-name-preserving widening; terminal seal in existing trigger.
- QA-Security ✅ — Hash-bound PORTAL_TOKEN, method consistency CHECK, append-only, org-scoped RLS.
- Business ✅ — Terminal `acknowledged` status unlocks AR "Pending Acknowledgement" filter.
- Lead Reviewer ✅ — Council-approved plan (Sprint A, this migration).

## Run Command

```bash
make test-db
```
