# Test Plan: portal_sealed_message

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260823000003_portal_sealed_message.sql` | `20260823000003_portal_sealed_message_test.sql` | ✅ |

## Intent

When a verdict is sealed internally the portal token is revoked in the same
transaction (`20260823000002`). Previously `read_dispute_portal` collapsed revoked
→ generic `Portal access denied.`, giving the carrier no closure. This migration
adds a sealed-state branch: a revoked token whose sanction reached a TERMINAL
verdict (`applied` | `rejected` | `acknowledged`) returns

```json
{ "closed": true, "closed_reason": "JUDGED_INTERNALLY",
  "dispute_summary": { "status": "<terminal>" } }
```

The frontend renders "SLA encerrado. Sanção julgada internamente." and hides
upload/submit. Anti-oracle (INV-26) is preserved: forged/expired tokens and
revoked-but-non-terminal tokens still collapse to the generic deny.

## Test Scenarios

| # | Category | Scenario | Expected | INV |
|---|----------|----------|----------|-----|
| T1 | Sealed | revoked token over `applied` sanction | returns payload (no deny) | INV-26 |
| T2 | Sealed | `closed` flag | `true` | — |
| T3 | Sealed | `closed_reason` | `JUDGED_INTERNALLY` | — |
| T4 | Sealed | surfaced status | `applied` | — |
| T5 | Anti-oracle | revoked token over still-`disputed` sanction | generic deny | INV-26 |
| T6 | Anti-oracle | unknown/forged token | generic deny | INV-26 |

## Council Sign-off

- **Architect:** closed branch reads only whitelisted status; no fine/storage leakage ✅
- **Senior:** branch reachable only after the NOT-FOUND/expired generic denies; advisory lock preserved on every path ✅
- **QA/Security:** terminal-status gate prevents oracle; token holder already proved possession → closure is owed, not enumeration ✅
- **Lead Reviewer:** `pr_scanner: ignore-regression` justified — `CREATE OR REPLACE`, signature unchanged ✅
