# Test Plan: portal_submission_rpcs_ledger (Sprint A M5 — Portal + De Acordo)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260817000005_portal_submission_rpcs_ledger.sql` | `20260817000005_portal_submission_rpcs_ledger_test.sql` | ✅ |

## Intent

Wires the full portal counter-evidence pipeline and the "De Acordo" flow. Every
state mutation is an atomic SECURITY DEFINER RPC (row + ledger fact in one
transaction), so the edge functions stay thin and every path is pgTAP-testable
without Deno. Adds portal provenance to `dispute_evidence_attachments`
(`uploaded_by` nullable + `submission_id` FK, sealed), widens `chk_ledger_type`
(H1 swap, canonical name) with 8 new types, and a `portal_mime_ext` helper.

RPCs: `create_portal_submission` (service_role, mint QUARANTINE + signed-URL
path, per-token cap, submit-scope gate), `register_portal_evidence`
(service_role, finalize OK → VERIFIED attachment + PENDING_AUDIT, idempotent,
production path derived from sealed fields), `fail_portal_submission`
(service_role, MISMATCH/REJECTED, never attaches), `audit_portal_submission`
(authenticated, ACCEPT/REJECT, reject soft-deletes attachment),
`acknowledge_via_portal` (anon+auth, hash-bound to the served
DISPUTE_PORTAL_TOKEN_ACCESSED snapshot, idempotent),
`acknowledge_sanction_internal` (TENANT_ADMIN, off-band, no hash).

## Test Scenarios (32 assertions)

| # | Category | Scenario | INV |
|---|----------|----------|-----|
| W1/W2 | Widening | `chk_ledger_type` admits new types, canonical name | INV-3 |
| D1/D2 | Provenance | dea `submission_id` column; `uploaded_by` nullable | INV-9 |
| CS1/CS2 | Submit | submission returns id; path `{token_id}/...` (no org_id) | INV-22 |
| CS3 | Submit | read token rejected on submit endpoint (scope) | INV-26 |
| CS4a/CS4b | Submit | per-token submission cap enforced | availability |
| RP1–RP4 | Finalize | PENDING_AUDIT, VERIFIED, portal provenance, FINALIZED fact | INV-3/9 |
| RP5 | Finalize | register replay idempotent | INV-15 |
| FP1–FP4 | Fail | MISMATCH, no attachment, HASH_MISMATCH fact | INV-9 |
| AP1–AP4 | Audit | accept→ACCEPTED, reject→REJECTED + attachment soft-deleted | INV-3 |
| AP5 | Audit | cross-org audit rejected | INV-22/26 |
| AK1 | De Acordo | unserved snapshot hash rejected | INV-9 |
| AK2/AK3 | De Acordo | queue→acknowledged, SANCTION_ACKNOWLEDGED fact | INV-3 |
| AK4 | De Acordo | portal ack idempotent | INV-15 |
| AI1/AI2 | Internal | TENANT_ADMIN internal ack → acknowledged | - |
| AI3 | Internal | AUDITOR cannot record internal ack | INV-26 |
| GR1/GR2 | Grants | service_role-only create; anon+auth ack | INV-DATA-API-GRANT |

## Council Sign-off

- Architect ✅ — RPC-encapsulated state machine; edge fns thin; chain of custody intact.
- Senior ✅ — H1 canonical widening; derived production paths; idempotent finalize/ack.
- QA-Security ✅ — Server hash canonical (INV-9), scope gate, anti-oracle 42501, hash-bound ack.
- Business ✅ — Closes counter-evidence intake + De Acordo (AR unlock).
- Lead Reviewer ✅ — Council-approved plan (Sprint A, this migration).

## Run Command

```bash
make test-db
```
