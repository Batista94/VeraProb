# Test Plan — Migration `20260801000001_csv_import_field_expansion.sql`

**Migration:** `20260801000001_csv_import_field_expansion.sql`
**Owner:** Council (Architect + Senior Engineer + QA/Security)
**Date:** 2026-08-01
**Status:** Pending Council sign-off

---

## Reason

The Universal CSV Importer exposed mappable target fields with no backing
column (`notes` on every entity, `operatorDocument`/`operatorPhone` on driver),
silently dropping the value at persist. This migration closes the gap for the
high-value, market-standard fields and enforces the contractor business key:

- `drivers`: `cpf` (identity), `phone`, `license_category`, `license_expiry_utc`
  (an expired CNH is operational-risk evidence — forensic value).
- `contracts`: `notes` (free-form observations).
- `contractors.tax_id` → `NOT NULL` (it is the FK business key resolved by every
  contract import; without it a contractor can never be linked).

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-1 | `organization_id` forced to `p_org_id`; JWT org must match when present |
| INV-2 | `SECURITY INVOKER` preserved on both replaced RPCs (RLS of caller applies) |
| INV-6 | `license_expiry_utc` is `TIMESTAMPTZ` |
| INV-16 | Set-based (batch) upsert unchanged |
| INV-22 | Org-scoped conflict keys unchanged — no cross-tenant write |
| INV-DB | Additive DDL only; `tax_id` NOT NULL via 3-step CHECK NOT VALID pattern |

---

## QA/Security — Exploit Paths Closed

1. **Silent data loss on import:** Operators mapped CPF/CNH/notes columns and the
   value vanished. **Closure:** columns now exist; dropped fields removed from
   `forEntity` (CsvTargetField) so the UI never offers a non-persisting target.
2. **Unlinkable contractor (integrity):** A contractor imported without CNPJ
   could never be referenced by a contract FK. **Closure:** `tax_id NOT NULL`
   at the DB + `contractorDocument` added to `requiredForEntity('contractor')`
   so the preflight gate blocks it before persist.
3. **Server-clock substitution on CNH expiry:** **Closure:** `license_expiry_utc`
   parsed and normalised to UTC ISO-8601 in `CsvRowMapper` (INV-6); column is
   `TIMESTAMPTZ` with no DEFAULT.

---

## Schema Delta

| Table | Column | Type | Null |
|-------|--------|------|------|
| drivers | cpf | TEXT | yes |
| drivers | phone | TEXT | yes |
| drivers | license_category | TEXT | yes |
| drivers | license_expiry_utc | TIMESTAMPTZ | yes |
| contracts | notes | TEXT | yes |
| contractors | tax_id | TEXT | **NO (changed)** |

RPCs replaced: `batch_upsert_drivers`, `batch_upsert_contracts` (recordset +
INSERT + UPDATE extended; signatures `(uuid, jsonb)` unchanged).

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260801000001_csv_import_field_expansion_test.sql` — `plan(N)`:

1. New columns exist with the declared type (`col_type_is`).
2. `contractors.tax_id` is NOT NULL (`col_not_null`).
3. `drivers.license_expiry_utc` is `timestamptz` (INV-6).
4. `batch_upsert_drivers` persists `cpf`/`phone`/`license_category`/
   `license_expiry_utc` on both the external_id and natural-key paths.
5. `batch_upsert_contracts` persists `notes` on both paths.
6. Both replaced RPCs remain `SECURITY INVOKER` (`prosecdef = false`).
7. `authenticated` retains `EXECUTE` on both replaced RPCs.

> Local pgTAP note: `col_is_nullable` is unavailable in this environment; use
> `col_not_null` / `col_has_default` assertions instead.

---

## Application-Layer Tests

| Test | Location | Assertion |
|------|----------|-----------|
| operator mapper emits cpf/phone/license_category(upper)/license_expiry_utc(ISO UTC) | `test/application/admin/csv_row_mapper_test.dart` | DB-shaped map keys present |
| contract mapper emits `notes` | `test/application/admin/csv_row_mapper_test.dart` | `notes` present |
| `forEntity` no longer offers `notes` for asset/operator/contractor/zone, nor `zoneCode` | `test/domain/enums/csv_target_field_scope_test.dart` | scope isolation |
| `requiredForEntity('contractor')` includes `contractorDocument` | `test/domain/enums/csv_target_field_test.dart` | coverage gate |
| preflight validates CNH category + CNH expiry as date | `test/application/admin/csv_preflight_validator_test.dart` | `invalid_license_category` / `invalid_date` |

---

## Rollback Plan

> [!CAUTION]
> Columns are additive and nullable except `contractors.tax_id`. To roll back the
> NOT NULL: `ALTER TABLE public.contractors ALTER COLUMN tax_id DROP NOT NULL;`
> then `ALTER TABLE public.contractors DROP CONSTRAINT contractors_tax_id_not_null;`.
> RPC rollback: re-apply the `20260730000002` definitions. New columns may be left
> in place (harmless) or dropped only after a release cycle with Council approval.

---

## Manual Verification Checklist

- [ ] `make test-db` passes with new pgTAP suite
- [ ] `supabase db diff` shows the 5 new columns + tax_id NOT NULL + 2 replaced functions, no drops
- [ ] `supabase/types.database.ts` regenerated + committed
- [ ] `flutter analyze` zero warnings
- [ ] `flutter test test/application/admin test/domain/enums` green
- [ ] `bash scripts/security/pr_full_scanner.sh` passes
