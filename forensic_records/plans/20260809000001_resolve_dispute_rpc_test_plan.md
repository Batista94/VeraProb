# Test Plan — Migration `20260809000001_resolve_dispute_rpc.sql`

**Migration:** `20260809000001_resolve_dispute_rpc.sql`
**Owner:** Council (Architect + Senior Engineer + QA/Security)
**Date:** 2026-06-09
**Status:** Pending Council sign-off
**Spec:** Consistência Transacional Pura (Resolução de Disputas) — Fase 10.8

---

## Reason

The legacy dispute-resolution flow (`accept`/`overturn`/`retract`) ran as 3–4
independent PostgREST round-trips in `ResolveDisputeHandler`: a non-locking
TOCTOU read (`_assertCurrentDisputeUnresolved`), a ledger append, a queue
status update, and (overturn only) a second snapshot-seal RPC. Each is a
separate implicit transaction. This opened two Enterprise-grade forensic
defects:

1. **TOCTOU race (INV-3 corruption):** two auditors resolving the same disputed
   sanction concurrently both pass the read, both append a resolution fact, and
   both flip the queue — producing **duplicate resolution facts in an
   append-only ledger**.
2. **Non-atomicity (INV-21 break):** a crash between the ledger append and the
   queue update (or the overturn snapshot seal) leaves orphaned ledger rows, a
   card stuck at `disputed`, or a `DISPUTE_OVERTURNED` fact without its snapshot.

This migration introduces the `public.resolve_dispute(...)` SECURITY DEFINER
RPC, which performs **lock → status re-check → ledger append → queue update →
(overturn) inline snapshot seal** in ONE transaction, with row-level locking.

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-3 | The RPC only `INSERT`s the resolution fact; no `UPDATE`/`DELETE` on the ledger. Exactly one fact per resolution. |
| INV-1 | `org_id` re-asserted from `auth.jwt() -> 'app_metadata' ->> 'org_id'` (SECURITY DEFINER bypasses RLS). |
| INV-22 | Cross-tenant resolve attempt rejected; Tenant-A never mutates Tenant-B. |
| INV-26 | Anti-oracle: wrong-org AND not-found both raise `42501` (`insufficient_privilege`) — indistinguishable. |
| INV-10 | Concurrent loser raises `P0001` + DETAIL `IdempotencyProcessingException`; maps to the typed domain exception. |
| INV-6 | `occurred_at_utc` supplied by the caller (`IDateTimeProvider.nowUtc()`); never `NOW()` inside the RPC. |
| INV-15 | Ledger payload (`queue_entry_id`, `resolved_by_user_id`, `actor_email`, `resolution_reason`, `verdict_evidence`) is byte-identical to `SlaLedgerMapper._resolution`. |
| INV-21 | Overturn arc seals the forensic snapshot inline (same txn) linked to the just-appended ledger id. |
| INV-DB | Defense-in-depth unique indexes are per-partition, partial, and additive (no blocking ALTER/DROP). |

---

## Auth Posture (Max Hardening — user decision)

- **NULL JWT rejected:** a caller without `app_metadata.org_id` is rejected (`42501`).
- **No `service_role`/`anon` grant:** `REVOKE ALL … FROM PUBLIC` + `GRANT EXECUTE … TO authenticated` only. A service_role JWT carries no tenant claim → cannot pass the guard. No Data-API bypass path.
- **Server-side RBAC re-check:** role MUST be `TENANT_ADMIN` or `AUDITOR`; otherwise `42501`.

---

## QA/Security — Exploit Paths Closed

1. **Double-resolution race:** `SELECT … FOR UPDATE` on the queue row is the first
   access. The second concurrent caller blocks, then re-reads a non-`disputed`
   status and loses with `IdempotencyProcessingException`. No second ledger fact.
2. **Cross-tenant resolution:** `p_organization_id` is compared to the JWT org;
   mismatch → `42501`. Lookup is also org-scoped, so a wrong-org id is a not-found
   (same `42501`) — no enumeration oracle (INV-26).
3. **Privilege escalation:** OPERATOR (or any non-admin/auditor) → `42501`.
4. **Direct duplicate INSERT (bypassing the RPC):** the per-partition partial
   unique indexes raise `23505` on a second resolution fact for the same
   `(organization_id, queue_entry_id)`.
5. **NULL-JWT seal bypass via the inline overturn path:** closed by the companion
   migration `20260809000002` (hardened `seal_dispute_resolution_snapshot` guard).

---

## Atomicity / Rollback Semantics

- The RPC body runs inside the PostgREST implicit transaction. Any failure
  (ledger CHECK, FK, snapshot seal error) rolls back the ledger append, the queue
  update, and the snapshot together — no partial state is ever observable.
- The overturn snapshot seal is a plpgsql sub-call, so it executes in the
  **caller's** transaction (the FK `forensic_evidence_snapshots → sla_audit_ledger_v2`
  is satisfiable because the ledger row already exists in the same txn).

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260809000001_resolve_dispute_rpc_test.sql`

1. **Function exists** with the expected signature and is `SECURITY DEFINER`.
2. **Grants:** `authenticated` has EXECUTE; `anon`/`service_role` do NOT.
3. **Happy path (accept):** disputed → `rejected`; exactly one `DISPUTE_ACCEPTED`
   fact; `reviewed_at`/`reviewed_by`/`rejection_reason` set.
4. **Idempotency:** a second call on the now-`rejected` row raises `P0001`.
5. **Cross-tenant:** call with a mismatched org under a tenant JWT → `42501`.
6. **Wrong role:** OPERATOR JWT → `42501`.
7. **Defense-in-depth:** a direct duplicate resolution INSERT → `23505`.
8. **Determinism (INV-15):** the appended payload keys/values match the
   `SlaLedgerMapper` resolution output.

> Concurrency (TOCTOU) is proven at the integration layer:
> `test/integration/resolve_dispute_concurrency_test.dart` (1 success + 1
> `IdempotencyProcessingException`, exactly 1 ledger fact).

---

## Rollback Plan

```sql
DROP INDEX IF EXISTS public.uq_ledger_resolution_p0;
DROP INDEX IF EXISTS public.uq_ledger_resolution_p1;
DROP INDEX IF EXISTS public.uq_ledger_resolution_p2;
DROP INDEX IF EXISTS public.uq_ledger_resolution_p3;
DROP FUNCTION IF EXISTS public.resolve_dispute(
  UUID, UUID, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TEXT
);
```

---

## Manual Verification Checklist

- [ ] `make test-db` green (pgTAP assertions above).
- [ ] `flutter test test/integration/resolve_dispute_concurrency_test.dart` green.
- [ ] Overturn arc produces a ledger fact AND a snapshot in one txn.
- [ ] Scanner (`pr_full_scanner.sh`) green.
