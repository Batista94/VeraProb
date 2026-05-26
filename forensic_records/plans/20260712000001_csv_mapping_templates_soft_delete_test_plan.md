# Test Plan — 20260712000001_csv_mapping_templates_soft_delete

**Migration:** `supabase/migrations/20260712000001_csv_mapping_templates_soft_delete.sql`
**Invariants:** INV-1, INV-3, INV-DB

---

## Scope

Adds `deleted_at TIMESTAMPTZ NULL` to `csv_mapping_templates` and updates the RLS
policy so soft-deleted rows are invisible at the DB level (USING) while the soft-delete
UPDATE itself is permitted (WITH CHECK org-only).

---

## Test Cases

### SD1 — Soft-deleted row invisible to authenticated role (INV-1 + INV-3)

```sql
-- Insert active template
INSERT INTO public.csv_mapping_templates (organization_id, name, target_entity, column_mappings, created_by)
  VALUES ('a0000000-0000-0000-0000-00000000000a', 'T1', 'asset', '[]', '00000000-0000-0000-0000-000000000002');
-- Soft-delete it
UPDATE public.csv_mapping_templates SET deleted_at = now() WHERE name = 'T1';
-- SELECT must return 0 rows (RLS USING excludes deleted_at IS NOT NULL)
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates WHERE name = 'T1' $$,
  ARRAY[0],
  'SD1: Soft-deleted row invisible to authenticated role'
);
```

### SD2 — Active row still visible after another row is soft-deleted (INV-22)

```sql
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates WHERE name = 'T2' $$,
  ARRAY[1],
  'SD2: Active row unaffected by soft-delete of sibling row'
);
```

### SD3 — Hard DELETE blocked by RLS (USING excludes soft-deleted row)

```sql
-- Attempt to hard-delete a row that is already soft-deleted →
-- RLS USING filters it out → 0 rows affected, no error (PostgREST behavior).
-- Result must be 0 rows deleted (verify via count before/after).
SELECT results_eq(
  $$ SELECT count(*)::int FROM public.csv_mapping_templates $$,
  ARRAY[1],  -- only T2 remains; T1 soft-deleted and invisible
  'SD3: Count unchanged after attempted hard-delete of invisible row'
);
```

---

## Verification

- `make test-db` — all SD cases pass.
- Supabase Studio: insert template, UPDATE `deleted_at = now()`, confirm SELECT returns 0.
- Confirm `dart analyze` passes after Dart-layer changes (interface + repo + handler).
