# Test Plan — Migration `20260809000002_harden_seal_dispute_null_jwt.sql`

**Migration:** `20260809000002_harden_seal_dispute_null_jwt.sql`
**Owner:** Council (QA/Security lead)
**Date:** 2026-06-09
**Status:** Pending Council sign-off
**Spec:** Consistência Transacional Pura — pre-existing twin flaw (QA CRITICAL)

---

## Reason

`seal_dispute_resolution_snapshot` (migration `20260808000002`) shipped a
NULL-permissive tenant guard:

```sql
IF v_jwt_org IS NOT NULL AND v_jwt_org::uuid <> p_organization_id THEN
  RAISE EXCEPTION 'Cross-tenant seal rejected (INV-1/INV-22)' ...;
END IF;
```

A caller whose JWT carries no `app_metadata.org_id` (NULL JWT, e.g. a
`service_role` token or a pending-invite session) **skips the check entirely**
and can seal a forensic snapshot for **any** `organization_id`. This is a
tenant-isolation bypass (INV-1 / INV-22) on the forensic vault.

This migration `CREATE OR REPLACE`s the function with a fail-closed guard,
matching the `resolve_dispute` posture:

```sql
IF v_jwt_org IS NULL OR v_jwt_org::uuid <> p_organization_id THEN
  RAISE EXCEPTION 'Cross-tenant seal rejected (INV-1/INV-22)' ...;
END IF;
```

The function body is otherwise byte-identical to `20260808000002` — no
behaviour change for legitimate authenticated callers.

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-1 | `org_id` guard now mandatory (NULL JWT rejected). |
| INV-22 | Tenant isolation on the forensic vault restored. |
| INV-3 | Function still performs NO ledger append (snapshot-only). |
| INV-21 | Snapshot still linked to the supplied `ledger_entry_id`. |

---

## Compatibility / Blast Radius

- `resolve_dispute` calls this function inline under the **original caller's**
  JWT (an authenticated `TENANT_ADMIN`/`AUDITOR`), so the hardened guard passes
  for the overturn arc — no regression.
- The legacy `PostgresForensicEvidenceSnapshotRepository.sealForDispute` path
  (a direct PostgREST RPC) also runs under an authenticated user JWT — unaffected.
- Grants are unchanged (still `authenticated` + `service_role`); the NULL-JWT
  guard is what closes the bypass, not the grant set.

---

## Atomicity / Rollback Semantics

- `CREATE OR REPLACE FUNCTION` is atomic. No data is touched.

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260809000002_harden_seal_dispute_null_jwt_test.sql`

1. **NULL-JWT rejected:** invoking `seal_dispute_resolution_snapshot` with no
   `request.jwt.claims` set → `42501` (`insufficient_privilege`) — previously it
   would have proceeded.
2. **Cross-tenant rejected:** authenticated org-A JWT sealing for org-B → `42501`.
3. **Same-tenant authenticated still works:** org-A JWT sealing for org-A → succeeds
   (given a valid rule set), proving no regression for legitimate callers.

---

## Rollback Plan

> Append-only: the prior (vulnerable) definition is NOT restored. If a rollback
> is ever required, author a new forward migration. For reference, the previous
> guard used `IS NOT NULL AND` instead of `IS NULL OR`.

---

## Manual Verification Checklist

- [ ] `make test-db` green.
- [ ] Overturn arc via `resolve_dispute` still seals a snapshot (integration test).
- [ ] No regression in existing forensic-evidence snapshot tests.
