# Test Plan: portal_evidence_submissions (Sprint A M2 — Portal Submissão)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260817000002_portal_evidence_submissions.sql` | `20260817000002_portal_evidence_submissions_test.sql` | ✅ |

## Intent

Quarantine ledger for carrier-submitted counter-evidence. A row is born in
`QUARANTINE` when the carrier requests a signed upload URL, and is promoted only
after `portal-finalize-upload` re-downloads the bytes, sniffs magic bytes, and
recomputes SHA-256 **server-side** (INV-9). The carrier-declared mime/size/hash
are recorded but never canonical (zero-trust, INV-18).

Sealed-at-ingest fields are immutable; finalize/audit fields are **seal-once**
(NULL → value, then frozen) so finalize and the auditor decision are replay-safe.
Status is **monotonic**: `QUARANTINE → {PENDING_AUDIT|MISMATCH|REJECTED|EXPIRED}`,
`PENDING_AUDIT → {ACCEPTED|REJECTED}`; `ACCEPTED/REJECTED/MISMATCH/EXPIRED` are
terminal. RLS is **deny-all** — the quarantine table is service_role only (paths
must not leak); auditor reads go through a SECURITY DEFINER read model.

## Test Scenarios (21 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| S1 | Structure | table exists | `has_table` | - |
| S2 | Structure | `sha256_server` column exists | `has_column` | INV-9 |
| S3 | Structure | `quarantine_storage_path` column exists | `has_column` | - |
| S4 | Structure | `status` default `QUARANTINE` | `information_schema` | - |
| S5 | Security | RLS enabled | `relrowsecurity` | INV-2 |
| S6 | Security | deny-all — zero policies | `count = 0` | INV-2/22 |
| S7 | Security | authenticated cannot SELECT | `NOT has_table_privilege` | INV-22 |
| S8 | Security | service_role can SELECT | `has_table_privilege` | INV-DATA-API-GRANT |
| C1 | Constraint | invalid declared mime rejected | `throws 23514` | INV-18 |
| C2 | Constraint | malformed `sha256_client` rejected | `throws 23514` | INV-9 |
| C3 | Constraint | oversize declared file rejected | `throws 23514` | - |
| C4s | Constraint | first submission inserts | `lives_ok` | - |
| C4 | Constraint | duplicate token+path rejected | `throws 23505` | anti-replay |
| IM1 | Immutability | sealed `sha256_client` mutation blocked | `throws 23001` | INV-9 |
| IM2 | Immutability | seal-once `sha256_server` re-mutation blocked | `throws 23001` | INV-9 |
| ST1 | Lifecycle | legal QUARANTINE → PENDING_AUDIT | `lives_ok` | INV-3 |
| ST2 | Lifecycle | illegal QUARANTINE → ACCEPTED blocked | `throws 23001` | INV-3 |
| ST3 | Lifecycle | terminal MISMATCH cannot transition | `throws 23001` | INV-3 |
| ST4 | Lifecycle | legal PENDING_AUDIT → ACCEPTED | `lives_ok` | INV-3 |
| DEL | Append-only | hard DELETE blocked | `throws 23001` | INV-3 |
| RES | Append-only | soft-delete resurrection blocked | `throws 23001` | INV-3 |

## Council Sign-off

- Architect ✅ — Quarantine entity mirrors `dispute_evidence_attachments`; no Core leak.
- Senior ✅ — Seal-once finalize fields = replay-safe finalize; explicit transition table.
- QA-Security ✅ — Deny-all RLS, zero-trust declared metadata, server hash canonical (INV-9).
- Business ✅ — Quarantine → audit pipeline unblocks portal counter-evidence intake.
- Lead Reviewer ✅ — Council-approved plan (Sprint A, this migration).

## Run Command

```bash
make test-db
```
