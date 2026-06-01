# Test Plan — Migration `20260801010000_forensic_evidence_vault.sql`

**Migration:** `20260801010000_forensic_evidence_vault.sql`
**Owner:** Council (Architect + Senior Engineer + QA/Security)
**Date:** 2026-08-01
**Status:** Pending Council sign-off
**Spec:** `.kiro/specs/forensic-evidence-snapshot/requirements.md` (Req 1–13)

---

## Reason

Forensic Evidence Snapshot Vault. At verdict-seal time the active SLA rule is
frozen and cryptographically bound to the infraction so a later contract
renegotiation cannot rewrite a historical verdict. A single Backend-Authority
RPC (`seal_forensic_evidence`) atomically appends the verdict ledger entry,
resolves the active rule from the DB (ignoring any client-supplied content),
computes a SHA-256 integrity hash, and persists the snapshot — all in one
transaction. The vault is append-only and immutable even to privileged roles.

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-1 | `organization_id` on every row; in-RPC JWT guard rejects cross-tenant seal |
| INV-2 | Read RLS via `auth.jwt() -> 'app_metadata' ->> 'org_id'`; verify RPC is INVOKER |
| INV-3 | Append-only: BEFORE UPDATE/DELETE triggers reject all mutation |
| INV-6 | All datetime columns `TIMESTAMPTZ`; `sealed_at_utc` server-clock authority |
| INV-9 | SHA-256 hash over canonical `snapshot::text` |
| INV-15 | Deterministic: `jsonb_agg(... ORDER BY evaluation_order)` + jsonb canonical text |
| INV-21 | Verdict (ledger entry) → snapshot id binding |
| INV-22 | Tenant-A never reads Tenant-B; red-team test |
| INV-26 | Cross-tenant / unknown verdict → empty (404 parity) |
| INV-DATA-API-GRANT | `authenticated` = SELECT only; writes via DEFINER RPC; service_role ALL |

---

## QA/Security — Exploit Paths Closed

1. **Insider UPDATE/DELETE of sealed evidence (Req 3, 9):** BEFORE UPDATE and
   BEFORE DELETE triggers `RAISE … restrict_violation` (`23001`) for *every* role
   incl. `service_role` — REVOKE alone is insufficient.
2. **Client-injected false rule (Req 5):** the RPC ignores all caller rule content
   and reads `contract_rule_sets` / `contract_rule_versions` directly; the request
   payload carries no rule fields.
3. **Cross-tenant seal via crafted `p_organization_id`:** in-function guard raises
   `42501` when JWT `app_metadata.org_id` is present and differs.
4. **Cross-tenant read:** read RLS policy scopes SELECT to the JWT org; a Tenant-B
   verdict id returns zero rows for Tenant-A.
5. **Orphan snapshot (Req 10.5):** composite FK `(organization_id, ledger_entry_id)`
   → `sla_audit_ledger_v2(organization_id, id)` makes a snapshot without a verdict
   impossible.
6. **Duplicate verdict/snapshot on retry (Req 6, 10.4):** `UNIQUE(org, idempotency_key)`
   + idempotency short-circuit returns the existing snapshot and appends no second
   ledger entry; the `unique_violation` handler covers the concurrent race without
   leaving an orphan ledger row.
7. **Silent tamper (Req 2.5, 8.5):** `verify_forensic_evidence` recomputes the hash
   over the stored snapshot and reports `tampered` on mismatch.

> **Hard-block logging limitation (Req 3.5 / 9.3):** a BEFORE trigger that RAISEs
> aborts the transaction and therefore cannot persist a rejection row in an
> application table. Rejected mutation attempts are captured by the Postgres
> server log / pgAudit (statement + role + error), not by an app table. A
> follow-up may add an asynchronous audit sink.

---

## Atomicity / Rollback Semantics (Req 10, 13)

| Scenario | Expected |
|----------|----------|
| Active rule missing | `P0002`; no ledger entry, no snapshot |
| Snapshot INSERT fails | whole txn rolls back incl. the ledger append |
| Concurrent duplicate idempotency key | second caller returns the persisted snapshot; no orphan ledger row |
| Committed verdict | exactly one snapshot (UNIQUE `(org, ledger_entry_id)`) |

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260801010000_forensic_evidence_vault_test.sql`:

1. Table + both RPCs exist; `seal_forensic_evidence` is `SECURITY DEFINER`,
   `verify_forensic_evidence` is `SECURITY INVOKER`.
2. Grants: `authenticated` has SELECT, **lacks** INSERT/UPDATE/DELETE; holds
   EXECUTE on both RPCs (INV-DATA-API-GRANT).
3. Seal happy path: returns a row; `integrity_hash` is 64-hex; exactly one ledger
   entry + one snapshot created.
4. Idempotency: second seal with the same key returns the same snapshot id and
   creates **no** second ledger entry.
5. Immutability: `UPDATE` and `DELETE` on a sealed row both `throws_ok '23001'`.
6. Missing rule: seal for a contract with no active rule → `P0002`; no rows written.
7. Orphan guard: direct INSERT with a non-existent `ledger_entry_id` → FK violation.
8. Hash verification: `verify_forensic_evidence` returns `status = 'authentic'`
   and `stored_hash = computed_hash` for an untouched row.
9. Cross-tenant seal: authenticated caller, mismatched `request.jwt.claims` org →
   `42501`.
10. Cross-tenant read (INV-22): Tenant-B authenticated caller sees zero rows for a
    Tenant-A snapshot (404 parity, INV-26).

Trusted write paths run as `postgres` (RLS bypass; `auth.jwt()` NULL → guard
permits). Cross-tenant cases run under `authenticated` with crafted
`request.jwt.claims`.

---

## Application-Layer Tests

| Test | Location | Assertion |
|------|----------|-----------|
| Entity hash determinism + equality | `test/domain/sla_audit/forensic_evidence_snapshot_test.dart` | canonical Dart hash stable; `fromJson`/`toJson` round-trips; UTC + non-empty guards raise `IntegrityException` |
| Handler idempotency / tenant validation | `test/application/sla_audit/seal_forensic_evidence_handler_test.dart` | double-seal → single repo call result; non-UTC / empty org rejected |
| Repo org-scoping | `test/infrastructure/sla_audit/postgres_forensic_evidence_snapshot_repository_test.dart` | read URL carries `organization_id=eq.<org>`; `rpc('seal_forensic_evidence')` invoked with mapped params; `verify` maps tampered → `IntegrityException` |

---

## Rollback Plan

> [!CAUTION]
> Rollback (pre-production only): `DROP FUNCTION IF EXISTS public.seal_forensic_evidence(...)`,
> `DROP FUNCTION IF EXISTS public.verify_forensic_evidence(uuid, uuid)`,
> then `DROP TABLE IF EXISTS public.forensic_evidence_snapshots`. Once any verdict
> is sealed in production the table is legally retained (Req 15) — no drop.

---

## Manual Verification Checklist

- [ ] `make test-db` passes with the new pgTAP suite
- [ ] `supabase db diff` shows 1 new table, 2 functions, 2 immutability triggers, RLS policy, grants — no drops
- [ ] `bash scripts/sync_db_types.sh` regenerated `supabase/types.database.ts`
- [ ] `flutter analyze` zero warnings after domain/app/infra wiring
- [ ] `bash scripts/security/pr_full_scanner.sh` green
