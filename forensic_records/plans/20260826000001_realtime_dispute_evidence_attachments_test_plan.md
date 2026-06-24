# Test Plan: realtime_dispute_evidence_attachments (PKG3 — Dispute Reality)

## Migration Coverage

| Migration | pgTAP File | Status |
|-----------|-----------|--------|
| `20260826000001_realtime_dispute_evidence_attachments.sql` | `20260826000001_realtime_dispute_evidence_attachments_test.sql` | ✅ |

## Intent

The auditor queue (`_PortalSubmissionsZone`) listed PENDING_AUDIT portal
counter-evidence only on first build and after the auditor accepted/rejected a
tile — a contraprova that arrived while the auditor stared at the card stayed
invisible until a manual reload. PKG3 closes that gap with realtime refresh.

`portal_evidence_submissions` is **deny-all RLS** (quarantine paths must not
leak), so the authenticated client cannot stream it. `register_portal_evidence`
inserts a row into `dispute_evidence_attachments` 1:1 when it promotes a
submission to PENDING_AUDIT; that table is authenticated-readable and
tenant-scoped (`dea_select_own_org`). This migration publishes it on
`supabase_realtime` so the Flutter side gets an INSERT tick per finalized
submission and invalidates the matching `pendingPortalSubmissionsProvider`
family entry.

INV-16: a SINGLE shared `portalEvidenceRealtimeProvider` channel serves every
disputed card — never one subscription per card. INV-22: realtime
`postgres_changes` is gated by the table RLS, so Tenant-A never receives
Tenant-B inserts. No DDL touches the table; publication membership only, so
`types.database.ts` is unaffected.

## Test Scenarios (3 assertions)

| # | Category | Scenario | Assertion | INV |
|---|----------|----------|-----------|-----|
| P1 | Realtime | `dispute_evidence_attachments` is a member of `supabase_realtime` | `is(count,1)` via `pg_publication_tables` | INV-16 |
| P2 | Idempotency | migration is re-runnable (single membership row, no dupe) | `is(count,1)` | append-only |
| P3 | Security | RLS still enabled on the published table (realtime stays RLS-gated) | `is(relrowsecurity,true)` | INV-22 |

## Council Sign-off

- Senior ✅ — Reuses the proven `sanction_review_queue` publication idiom; no DDL on the table, idempotent ADD.
- QA-Security ✅ — Published table keeps RLS (`dea_select_own_org`); realtime `postgres_changes` is RLS-gated → no cross-tenant leak (INV-22). `portal_evidence_submissions` (deny-all) is deliberately NOT published.
- Lead Reviewer ✅ — Scoped, append-only, types unaffected.

## Run Command

```bash
make test-db
```
