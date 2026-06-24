# Test Plan: list_portal_submissions_with_justification (Dispute Portal → Tribunal fix — PKG2)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260827000002_list_portal_submissions_with_justification.sql` | `20260817000006_list_portal_submissions_rpc_test.sql` (hardened) | ✅ |

## Intent

The auditor review panel could read a portal counter-evidence **file** but not the
carrier's written **justification**: `list_portal_submissions` never projected
`portal_evidence_submissions.justification_text`. The testimony that ships with a
file submission was therefore invisible to the auditor — half the defense lost.

This migration adds `justification_text` to the RPC's projection. Because a
`RETURNS TABLE` column cannot be added with `CREATE OR REPLACE`, it is a
`DROP FUNCTION` + `CREATE` with the **same argument signature** `(uuid, uuid)` —
so PostgREST resolution and every committed caller are unaffected. Grant
re-asserted to `authenticated` (INV-DATA-API-GRANT). The text-only contest path
already had `list_portal_justification_submissions` (20260818000005); no change
there.

## Test Scenarios

Covered by the hardened `20260817000006_*_test.sql` (now `plan(7)`):

| # | Category | Assertion | INV |
|---|----------|-----------|-----|
| S1 | Signature | `list_portal_submissions(uuid,uuid)` exists (unchanged args) | — |
| S2 | Security | SECURITY DEFINER | INV-2 |
| HP | Read | only PENDING_AUDIT rows of own org listed (QUARANTINE excluded) | INV-22 |
| HP2 | Read | returns the finalized submission id | — |
| HP3 | Read | **`justification_text` is projected with the file submission** (new) | INV-1 |
| B1 | Anti-oracle | cross-org caller → 42501 | INV-22/26 |
| B2 | RBAC | non-auditor/admin role → 42501 | INV-22/26 |

Dart coverage (`make test`):

- `PortalSubmissionSummary.fromJson` parses `justification_text` (round-trip + null-tolerant).
- `PortalJustificationSummary.fromJson` round-trip (testimony-only contest) + Equatable + null timestamp.
- `pendingPortalJustificationsProvider` resolves via the injected gateway.

## Council Sign-off

- Architect ✅ — Read-only projection of an already-sealed column; no new state.
- Senior ✅ — `DROP`+`CREATE` keeps the arg signature; committed pgTAP hardened in the same package (no signature drift, `rpc_signature_drop_breaks_committed_tests`).
- QA-Security ✅ — Org + TENANT_ADMIN/AUDITOR gate preserved; anti-oracle 42501 parity intact (INV-22/26).
- Lead Reviewer ✅ — Scoped, `pr_scanner: ignore-regression` justified; `types.database.ts` regenerated.

## Run Command

```bash
make test-db && make test
```
