# Test Plan: portal_token_scope (Sprint A M1 — Portal Submissão + De Acordo)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260817000001_portal_token_scope.sql` | `20260817000001_portal_token_scope_test.sql` | ✅ |

## Intent

Extends the existing tokenized dispute portal so the same token mechanism can
both serve evidence (`token_scope = 'read'`) and accept counter-evidence
(`token_scope = 'submit'`). Adds a per-token submission cap (`max_submissions`).
Widens `generate_dispute_portal_token`'s read precondition from `disputed` to
`applied | disputed` — without this the acknowledgement ("De Acordo") flow,
which begins after a sanction is applied, would be unreachable.

`generate_portal_submit_token` is **TENANT_ADMIN only** (AUDITOR excluded —
submit outranks read) and still requires an active dispute. It reuses the
existing `DISPUTE_PORTAL_TOKEN_GENERATED` ledger fact with `token_scope` in the
payload, so no ledger-type widening is needed at this step.

## Test Scenarios (17 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| S1 | Structure | `token_scope` column exists | `has_column` | - |
| S2 | Structure | `max_submissions` column exists | `has_column` | - |
| S3 | Structure | `token_scope` is NOT NULL | `information_schema` | INV-7 |
| S3b | Structure | `token_scope` default is `read` | `information_schema` | - |
| S4 | Structure | submit-token RPC exists | `has_function` | - |
| S5 | Structure | submit-token RPC is SECURITY DEFINER | `prosecdef = true` | INV-2 |
| S6 | Constraint | invalid scope rejected | `throws 23514` | INV-7 |
| S7 | Constraint | submission cap out of `[1,20]` rejected | `throws 23514` | - |
| B1 | Auth/State | submit token for non-disputed → 42501 | state gate | INV-26 |
| B2 | Tenant | cross-org submit token → 42501 | tenant isolation | INV-22/26 |
| B3 | RBAC | AUDITOR cannot mint submit token → 42501 | submit > read | INV-26 |
| HP | Happy | TENANT_ADMIN mints submit token | `lives_ok` | - |
| V1 | Behavior | minted token `token_scope = submit` | `is` | - |
| V2 | Behavior | `max_submissions` persisted from param | `is = 7` | - |
| L1 | Audit | ledger fact GENERATED (submit) logged | count = 1 | INV-3 |
| IM | Immutability | `token_scope` sealed → mutation blocked | `restrict_violation` | INV-3 |
| W1 | Precondition | read token issuable for `applied` sanction | `lives_ok` | - |

## Council Sign-off

- Architect ✅ — Reuses token table + ledger type; no new entity, scope is a column.
- Senior ✅ — Sealed columns in immutability trigger; signature-stable widening.
- QA-Security ✅ — TENANT_ADMIN-only submit, disputed gate, anti-oracle 42501.
- Business ✅ — Unlocks the De Acordo flow (applied-status read token).
- Lead Reviewer ✅ — Council-approved plan (Sprint A, this migration).

## Run Command

```bash
make test-db
```
