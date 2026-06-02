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
| INV-9 | SHA-256 hash over the JCS (RFC 8785) canonical form via `jsonb_canonical_text` |
| INV-15 | Deterministic: `jsonb_agg(... ORDER BY evaluation_order)` + JCS canonical text (engine-independent, reproducible in Dart) |
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
   over the stored snapshot and reports `tampered` on mismatch. Proven against a
   trigger-bypass forgery in pgTAP (test 11): even when the immutability trigger is
   administratively disabled and the snapshot mutated, verification exposes it.
8. **SQL injection via free-text params (`p_set_id`, `p_verdict_type`):** the RPC is
   pure parameterized plpgsql — no `EXECUTE format(...)`, no string concatenation
   into SQL, and `search_path` pinned to `public, extensions` (defeats the classic
   SECURITY DEFINER search-path hijack). A red-team payload (`'; DROP TABLE …; --`)
   must land as inert literal data. Proven in pgTAP (tests 32-34): the seal commits
   normally, the vault table survives the embedded DROP, and the payload is stored
   verbatim in the snapshot — confirming it was bound, never interpreted.

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
11. **Tamper detection (Req 2.5 / 8.5):** the immutability trigger is administratively
    `DISABLE`d, the sealed `snapshot` is mutated in place, the trigger re-enabled;
    `verify_forensic_evidence` still reports `status = 'tampered'` and the recomputed
    hash diverges from the sealed hash. This is the last line of defense for the
    insider/superuser who circumvents the BEFORE trigger.
12. **Rule-window boundary (Req 5.3 / 12.2):** a rule set whose only version is active
    over the half-open interval `[active_from, active_to)`; seal at `occurred ==
    active_from` (inclusive → seals), `occurred < active_from` (`P0002`), `occurred <
    active_to` (seals), `occurred == active_to` (exclusive → `P0002`). Pins the exact
    `<=` / `>` boundary semantics against an off-by-one on the verdict timestamp.
13. **Canonical key ordering (Req 11):** `jsonb_canonical_text('{ "b":2,"a":1,"c":3 }')`
    returns `{"a":1,"b":2,"c":3}` — keys lexicographically sorted, insignificant
    whitespace stripped. This is the property that makes the SHA-256 reproducible
    outside Postgres (the DB's native `jsonb::text` orders keys by length/bytewise
    and is not portable).
14. **Canonical recursion (Req 11 / INV-15):** nested objects and array elements are
    canonicalized recursively (`{"z":[{"y":1,"x":2}],"a":"v"}` →
    `{"a":"v","z":[{"x":2,"y":1}]}`), so the frozen `rules` array + each `rule_config`
    hash deterministically regardless of source key order.
15. **SQL injection red-team (tests 32-34):** seal with a quote-breakout payload
    (`set-x'; DROP TABLE public.forensic_evidence_snapshots; --`) in the free-text
    `p_set_id`. (32) the seal commits normally, (33) `has_table` confirms the vault
    survives — the embedded DROP never executed, and (34) the payload is stored
    verbatim in `snapshot.set_id`. Proves the parameterized RPC binds the value as
    inert data; combined with the pinned `search_path`, the SECURITY DEFINER path is
    not injectable.

Trusted write paths run as `postgres` (RLS bypass; `auth.jwt()` NULL → guard
permits). Cross-tenant cases run under `authenticated` with crafted
`request.jwt.claims` (cleared with `RESET request.jwt.claims` afterwards, since
`RESET ROLE` does not touch GUCs).

---

## Application-Layer Tests

| Test | Location | Assertion |
|------|----------|-----------|
| Entity hash determinism + equality | `test/domain/sla_audit/forensic_evidence_snapshot_test.dart` | canonical Dart hash stable; `fromJson`/`toJson` round-trips; UTC + non-empty guards raise `IntegrityException` |
| Handler idempotency / tenant validation | `test/application/sla_audit/seal_forensic_evidence_handler_test.dart` | double-seal → single repo call result; non-UTC / empty org rejected |
| Repo org-scoping | `test/infrastructure/sla_audit/postgres_forensic_evidence_snapshot_repository_test.dart` | read URL carries `organization_id=eq.<org>`; `rpc('seal_forensic_evidence')` invoked with mapped params; `verify` maps tampered → `IntegrityException` |
| Repo seal round-trip (live DB) | same file (integration, skipped when Supabase offline) | seeds an active rule, calls `seal`, asserts 64-hex hash + frozen rule, then `verify` → authentic — exercises both RPC param maps Dart→SQL (param-drift guard) |
| Repo concurrent seal (live DB) | same file (integration) | **6** `seal` futures with one idempotency key all resolve to the same snapshot id + ledger entry, and **exactly one** verdict row exists for that key — proves the `unique_violation` rollback leaves no orphan ledger entry (INV-11 race) |
| Cross-language hash parity (live DB) | same file (integration) | Dart recomputes SHA-256 over `canonicalJsonEncode(stored snapshot)` and reproduces the DB's `integrity_hash` byte-for-byte — proves the seal is verifiable by any RFC 8785 tool, not just Postgres (Req 11, INV-9 portability) |

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
