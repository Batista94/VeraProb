# Test Plan — Migration `20260730000002_csv_batch_upsert_rpcs.sql`

**Migration:** `20260730000002_csv_batch_upsert_rpcs.sql`
**Owner:** Council (Architect + Senior Engineer + QA/Security)
**Date:** 2026-07-30
**Status:** Pending Council sign-off

---

## Reason

Bloco 1D persistence. Five `SECURITY INVOKER` RPCs (`batch_upsert_<entity>`)
perform set-based, idempotent upserts for the CSV importer — one batch round
trip per entity (INV-16), keyed on `(organization_id, external_id)` with a
natural-key fallback when `external_id` is absent.

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-1 | `organization_id` forced to `p_org_id`; JWT org must match when present |
| INV-2 | `SECURITY INVOKER` — RLS of the calling tenant applies |
| INV-16 | Set-based (batch) upsert; no row-by-row writes |
| INV-22 | No cross-tenant write — guard (42501) + RLS + org-scoped conflict keys |

---

## QA/Security — Exploit Paths Closed

1. **Cross-tenant write via crafted `p_org_id`:** An authenticated caller passes
   another tenant's UUID. **Closure:** the inline guard raises `42501` when the
   JWT `app_metadata.org_id` is present and differs from `p_org_id`; RLS WITH
   CHECK would also reject the row.
2. **RLS bypass via SECURITY DEFINER:** **Closure:** all five functions are
   `SECURITY INVOKER` (asserted via `pg_proc.prosecdef = false`).
3. **Silent duplication on re-import:** **Closure:** `ON CONFLICT … DO UPDATE`
   on `(organization_id, external_id)` (and the natural-key fallback) makes
   re-imports idempotent.

---

## Conflict-Key Matrix

| Entity | external_id target | Natural-key fallback |
|--------|--------------------|----------------------|
| vehicles | (org, external_id) | (org, plate) |
| drivers | (org, external_id) | (org, license_number) |
| contractors | (org, external_id) | (org, name) |
| contracts | (org, external_id) | (org, name, valid_from_utc) |
| operational_zones | (org, external_id) | (org, name) |

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260730000002_csv_batch_upsert_rpcs_test.sql` — `plan(13)`:

1. (1a–1e) All five RPCs exist with `(uuid, jsonb)` signature.
2. (2) All five are `SECURITY INVOKER`.
3. (3) `authenticated` holds `EXECUTE` on `batch_upsert_vehicles`.
4. (4a–4d) external_id idempotency: re-running the same `external_id` affects 1
   row, leaves a single row, and overwrites mutable fields (plate).
5. (5) Natural-key fallback dedups external_id-less rows on `(org, plate)`.
6. (6) Cross-tenant guard: authenticated caller with mismatched JWT org → `42501`.

Write paths execute as `postgres` (RLS bypass; `auth.jwt()` NULL → trusted
backend path permitted). The guard is exercised under the `authenticated` role
with a mismatched `request.jwt.claims` org.

---

## Application-Layer Tests

| Test | Location | Assertion |
|------|----------|-----------|
| Handler dispatches valid rows to the matching `batchUpsertFromCsv` once | `test/application/admin/import_csv_handler_test.dart` | repo called once (INV-16) |
| Row mapper coerces types + injects FK-resolved `contractor_name` | `test/application/admin/csv_row_mapper_test.dart` | per-entity DB-shaped maps |

---

## Rollback Plan

> [!CAUTION]
> Rollback: `DROP FUNCTION IF EXISTS public.batch_upsert_<entity>(uuid, jsonb);`
> for all five. No data dependency (functions only). Safe at any time before the
> importer relies on them in production.

---

## Manual Verification Checklist

- [ ] `make test-db` passes with new pgTAP suite
- [ ] `supabase db diff` shows 5 new functions, no table DDL, no drops
- [ ] `flutter analyze` zero warnings after repo wiring (Bloco 1D)
