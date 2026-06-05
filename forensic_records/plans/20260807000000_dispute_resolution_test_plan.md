# Test Plan — Migration `20260807000000_dispute_resolution.sql`

**Migration:** `20260807000000_dispute_resolution.sql`
**Owner:** Council (Architect + Senior Engineer + QA/Security)
**Date:** 2026-06-05
**Status:** Pending Council sign-off
**Spec:** Pacote 5 — Banco de Dados e Constraints

---

## Reason

Database adjustments for Dispute Resolution cycle. Introduces:
1. A partial index on `sanction_review_queue` for completed items (`status` in `'applied'`, `'rejected'`) sorted by `created_at DESC` to optimize the Completed tab queries.
2. A check constraint `chk_ledger_type` on `sla_audit_ledger_v2.type` to restrict type values to the known, supported domain event types in the application mapping, preventing any unrecognized or malformed action type insertion in the append-only ledger.

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-DB | Zero-Downtime Migration. Check constraint is added using `NOT VALID` to avoid blocking table scans on deployment. |
| INV-2 | Row Level Security (RLS) remains fully active. |
| INV-3 | Ledger remains append-only. No UPDATE/DELETE allowed. |

---

## QA/Security — Exploit Paths Closed

1. **Write/Insert of invalid action types:** The `chk_ledger_type` CHECK constraint validates every single `INSERT` into `public.sla_audit_ledger_v2`. Any attempt to insert an invalid or untracked type will throw a `check_violation` (SQLSTATE `23514`), securing the forensic ledger integrity.
2. **Query Performance Degradation:** The partial index `idx_srq_org_status_concluded_at` ensures queries filtering for completed rows (`applied` or `rejected`) are extremely fast and do not require scanning the entire queue table as the queue scales.

---

## Atomicity / Rollback Semantics

- If any step fails during the migration execution, PostgreSQL rolls back the entire transaction.
- The CHECK constraint is added as `NOT VALID`, meaning existing rows are not validated at creation time (ensuring zero downtime), but all subsequent insert operations are validated.

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260807000000_dispute_resolution_test.sql`

1. **Partial Index exists and structure matches:** Verify that the index `idx_srq_org_status_concluded_at` is successfully created and has a WHERE clause matching `'applied'` and `'rejected'`.
2. **CHECK constraint exists:** Verify that the constraint `chk_ledger_type` exists on `sla_audit_ledger_v2`.
3. **CHECK constraint works:** Verify that inserting an invalid type throws a `check_violation` (SQLSTATE `23514`).
4. **All 28 known types are accepted:** Sequence of `lives_ok` checks to verify all 28 mapped types (including the new dispute events and automated system events) can be inserted successfully.

---

## Rollback Plan

```sql
ALTER TABLE public.sla_audit_ledger_v2 DROP CONSTRAINT IF EXISTS chk_ledger_type;
DROP INDEX IF EXISTS public.idx_srq_org_status_concluded_at;
```

---

## Manual Verification Checklist

- [x] `make test-db` passes with the new pgTAP suite.
- [ ] `bash scripts/sync_db_types.sh` regenerated `supabase/types.database.ts`.
