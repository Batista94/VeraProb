# Test Plan: list_portal_submissions (Sprint A M6 — Auditor review)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260817000006_list_portal_submissions_rpc.sql` | `20260817000006_list_portal_submissions_rpc_test.sql` | ✅ |

## Intent

Safe read path over the deny-all `portal_evidence_submissions` quarantine table
for the auditor PENDING_AUDIT review panel. The table never grants client SELECT
(declared metadata / quarantine paths must not leak); this SECURITY DEFINER RPC
projects only the columns an auditor needs, scoped to the caller's org (INV-22),
and returns only `PENDING_AUDIT` rows. Pairs with `audit_portal_submission` (M5):
list → accept/reject.

## Test Scenarios (6 assertions)

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| S1 | Structure | RPC signature `(uuid,uuid)` | - |
| S2 | Structure | SECURITY DEFINER | INV-2 |
| HP | Behavior | only PENDING_AUDIT rows listed (QUARANTINE excluded) | - |
| HP2 | Behavior | returns the finalized submission id | - |
| B1 | Tenant | cross-org listing rejected | INV-22/26 |
| B2 | RBAC | non-auditor/admin role rejected | INV-26 |

## Council Sign-off

- Architect ✅ — Read model over deny-all table; no client SELECT leak.
- Senior ✅ — LEFT JOIN to live attachment; PENDING_AUDIT filter; org-scoped.
- QA-Security ✅ — JWT org + role gate, anti-oracle 42501, projection whitelist.
- Business ✅ — Unblocks the auditor accept/reject panel.
- Lead Reviewer ✅ — Council-approved plan (Sprint A, this migration).

## Run Command

```bash
make test-db
```
