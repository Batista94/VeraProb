# Test Plan: read_dispute_portal RPC (Item 5.3 — Anon Dispute Snapshot)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260814000003_read_dispute_portal_rpc.sql` | `20260814000003_read_dispute_portal_rpc_test.sql` | ✅ |

## Test Scenarios (7 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| T1 | Read | Valid token → snapshot JSONB | `IS NOT NULL` | INV-22 |
| T2 | Projection | Response excludes `fine_cents` | NOT LIKE | BIZ |
| T3 | Projection | Response excludes `storage_path` | NOT LIKE | INV-22 |
| T4 | Integrity | Self-referential `snapshot_hash` present | LIKE | INV-9 |
| T5 | Tracking | `access_count` increments per read | count = 4 | INV-3 |
| T6 | Audit | `DISPUTE_PORTAL_TOKEN_ACCESSED` logged once | count = 1 | INV-3 |
| T7 | Anti-Oracle | Revoked token → identical 42501 | `throws_ok` | INV-26 |

## Rationale

The portal RPC is the only `anon`-reachable surface in the dispute domain, so the
whitelist projection is load-bearing: T2/T3 prove the two highest-value leaks
(monetary exposure and storage layout) never reach an external party. T4 proves
the served payload carries its own SHA-256 for tamper-evidence; T6 proves the
first access seals a forensic "evidence was seen" fact (kills "I never saw it").
T7 proves every failure mode collapses to one indistinguishable error (anti-oracle).

## Council Sign-off

- Architect ✅ — Read-only projection, no transport leak into snapshot
- Senior ✅ — Pre-SELECT advisory lock, access tracking, first-access fact
- QA-Security ✅ — 7-vector threat model, timing normalization, whitelist
- Business ✅ — `fine_cents` exclusion (liability shield)
- Lead Reviewer ✅

## Run Command

```bash
make test-db
```
