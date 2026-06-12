# Test Plan: dispute_portal_tokens (Item 5.3 — Forensic Dispute Portal Backend)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260814000002_dispute_portal_tokens.sql` | `20260814000002_dispute_portal_tokens_test.sql` | ✅ |

> Sibling migrations have dedicated 1:1 plans: `20260814000001_portal_ledger_types_test_plan.md`
> (CHECK widening) and `20260814000003_read_dispute_portal_rpc_test_plan.md` (read RPC).
> This file's pgTAP also exercises generate/read/revoke end-to-end for integration depth.

## Test Scenarios (22 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| S1 | Structure | Table exists | `has_table` | - |
| S2 | Structure | RLS enabled | `relrowsecurity = true` | INV-2 |
| S3 | Structure | Generate RPC exists | `has_function` | - |
| S4 | Structure | Read RPC exists | `has_function` | - |
| S5 | Structure | Generate is SECURITY DEFINER | `prosecdef = true` | INV-2 |
| S6 | Structure | Read is SECURITY DEFINER | `prosecdef = true` | INV-2 |
| P1 | RLS | anon SELECT → 0 rows | deny-all | INV-2 |
| P2 | RLS | authenticated SELECT → 0 rows | deny-all | INV-2 |
| P3 | Generate | Non-disputed queue → 42501 | state gate | INV-26 |
| P4 | Generate | Cross-org → 42501 | tenant isolation | INV-22/26 |
| HP | Generate | Happy path succeeds | `lives_ok` | - |
| P12 | Audit | Ledger fact GENERATED logged | count = 1 | INV-3 |
| P8 | Read | Valid token → JSONB response | `IS NOT NULL` | INV-22 |
| P9 | Read | access_count incremented | count = 1 | INV-3 |
| P14 | Read | Response excludes fine_cents | NOT LIKE | BIZ |
| P7 | Read | Exhausted count → 42501 | anti-oracle | INV-26 |
| P5 | Read | Expired token → 42501 | anti-oracle | INV-26 |
| P13 | Revoke | Revocation succeeds + stamps | `lives_ok` + NOT NULL | INV-3 |
| P6 | Read | Revoked token → 42501 | anti-oracle | INV-26 |
| P10 | Immutability | Sealed field mutation → blocked | `restrict_violation` | INV-3 |
| P11 | Immutability | DELETE → blocked | append-only | INV-3 |

## Council Sign-off

- Architect ✅ — Pattern alignment with justification_submission_tokens
- Senior ✅ — Advisory lock, revocation, implementation
- QA-Security ✅ — Threat model (7 vectors), timing normalization, whitelist
- Business ✅ — Liability shield, fine_cents exclusion
- Lead Reviewer ✅ — All amendments incorporated

## Run Command

```bash
make test-db
```
