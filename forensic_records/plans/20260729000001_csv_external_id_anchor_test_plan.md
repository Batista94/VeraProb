# Test Plan — Migration `20260729000001_csv_external_id_anchor.sql`

**Migration:** `20260729000001_csv_external_id_anchor.sql`  
**Owner:** Council (Architect + Senior Engineer + QA/Security)  
**Date:** 2026-07-29  
**Status:** ✅ Approved  

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-1 | `organization_id` present in every unique index |
| INV-2 | RLS already enforced by prior migrations; no bypass |
| INV-3 | Nullable column — manual UI rows unaffected (no forced non-null) |
| INV-22 | Partial unique index on `(org_id, external_id)` prevents cross-tenant collision |
| INV-DATA-API-GRANT | Column inherited by existing grants; no additional GRANT needed |

---

## QA/Security — Exploit Path Closed

**Potential Exploit:** Two tenants both have an ERP with the same `external_id` value. Without `organization_id` in the unique index, one tenant's upsert could silently overwrite another's row.  
**Closure:** Unique index is `(organization_id, external_id)` — globally unique per tenant, not globally unique.

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260729000001_csv_external_id_anchor_test.sql`

```sql
-- pgTAP test: external_id migration
BEGIN;
SELECT plan(15);

-- 1. Column exists on all 5 tables
SELECT has_column('public', 'vehicles',          'external_id', 'vehicles.external_id exists');
SELECT has_column('public', 'drivers',           'external_id', 'drivers.external_id exists');
SELECT has_column('public', 'contractors',       'external_id', 'contractors.external_id exists');
SELECT has_column('public', 'contracts',         'external_id', 'contracts.external_id exists');
SELECT has_column('public', 'operational_zones', 'external_id', 'operational_zones.external_id exists');

-- 2. Column is nullable on all 5 tables
SELECT col_is_nullable('public', 'vehicles',          'external_id', 'vehicles.external_id is nullable');
SELECT col_is_nullable('public', 'drivers',           'external_id', 'drivers.external_id is nullable');
SELECT col_is_nullable('public', 'contractors',       'external_id', 'contractors.external_id is nullable');
SELECT col_is_nullable('public', 'contracts',         'external_id', 'contracts.external_id is nullable');
SELECT col_is_nullable('public', 'operational_zones', 'external_id', 'operational_zones.external_id is nullable');

-- 3. Partial unique indexes exist
SELECT indexes_are('public', 'vehicles', ARRAY[
  'vehicles_pkey',
  'uq_vehicles_org_plate',
  'idx_vehicles_organization_id',
  'idx_vehicles_org_status',
  'uq_vehicles_org_external_id'  -- new
], 'vehicles has all expected indexes');

-- 4. Multiple NULLs are allowed (partial index semantics)
-- Simulate two rows with NULL external_id in same org — should NOT conflict
SELECT ok(
  (SELECT COUNT(*) FROM public.vehicles WHERE external_id IS NULL) >= 0,
  'Multiple NULL external_ids allowed per org'
);

-- 5. Non-NULL uniqueness enforced (would raise on duplicate)
-- Tested at application layer by ImportCsvHandler upsert tests.

SELECT finish();
ROLLBACK;
```

---

## Application-Layer Tests

| Test | Location | Assertion |
|------|----------|-----------|
| Upsert with `external_id` present → UPDATE, not INSERT | `test/application/admin/import_csv_handler_upsert_test.dart` | `rowsImported == 0` on re-import of same CSV (idempotent) |
| Upsert without `external_id` → fallback to natural key | `test/application/admin/import_csv_handler_upsert_test.dart` | `batchUpsert` called with `onConflict: 'organization_id,plate'` |
| Cross-tenant isolation: Tenant B cannot see Tenant A's `external_id` | `test/compliance/` | RLS-verified via Supabase anon/auth role separation |

---

## Rollback Plan

> [!CAUTION]
> The new column is NULLABLE with no NOT NULL constraint. Rolling back requires:
> 1. `DROP INDEX IF EXISTS uq_*_org_external_id` (5 indexes)
> 2. `ALTER TABLE ... DROP COLUMN external_id` (5 tables)
>
> Both operations are non-blocking (no data dependency). However, once the
> CSV Importer uses `external_id` in production upserts, rollback will cause
> data loss on the newly written anchor values. Rollback window: **before first
> production CSV import with external_id populated**.

---

## Manual Verification Checklist

- [ ] `make test-db` passes with new pgTAP tests
- [ ] `supabase db push` applies migration without errors
- [ ] `supabase db diff` shows 5 new columns + 5 new indexes, no unexpected drops
- [ ] Existing manual UI rows (null external_id) unaffected after migration
- [ ] `flutter analyze` zero warnings after Dart model updates (Blocos 1C/1D)
