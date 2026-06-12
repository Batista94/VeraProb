# Test Plan: portal_ledger_types (Item 5.3 — Ledger CHECK Widening)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260814000001_portal_ledger_types.sql` | `20260814000001_portal_ledger_types_test.sql` | ✅ |

## Test Scenarios (6 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| T1 | Identity | Canonical constraint name survives rename-back | `chk_ledger_type` present on `sla_audit_ledger_v2` | INV-3 |
| T2 | Widen | `DISPUTE_PORTAL_TOKEN_GENERATED` accepted | `lives_ok` | INV-3 |
| T3 | Widen | `DISPUTE_PORTAL_TOKEN_ACCESSED` accepted | `lives_ok` | INV-3 |
| T4 | Widen | `DISPUTE_PORTAL_TOKEN_REVOKED` accepted | `lives_ok` | INV-3 |
| T5 | Guard | Unknown fact type rejected | `throws_ok` 23514 (check_violation) | INV-3 |
| T6 | Regression | Legacy `VERDICT_SEALED` still valid | `lives_ok` | INV-DB |

## Rationale

H1-safe widening (`ADD NOT VALID → VALIDATE → DROP old → RENAME`) must keep the
constraint **stable in name** (downstream pgTAP asserts the canonical
`chk_ledger_type`) and **strict in scope** — the new vocabulary is additive, the
constraint never degrades to a no-op (T5), and no pre-10.6 fact type regresses (T6).

## Council Sign-off

- Architect ✅ — Additive widening, canonical name preserved
- Senior ✅ — H1-safe ordering, no constraint-free window
- QA-Security ✅ — Constraint remains enforcing (T5)
- Lead Reviewer ✅

## Run Command

```bash
make test-db
```
