# Test Plan: csv_mapping_templates migration

**Migration:** `supabase/migrations/20260709000001_csv_mapping_templates.sql`
**Phase:** 10.4.B — Universal CSV Mapping Engine

## INV References

| INV | Aspect |
|-----|--------|
| INV-1 | `organization_id` tenant isolation |
| INV-2 | RLS via `auth.jwt() -> 'app_metadata' ->> 'org_id'` |
| INV-6 | TIMESTAMPTZ mandatory |
| INV-14 | Agnostic target fields |
| INV-DB | Non-destructive CREATE |
| INV-22 | Physical tenant isolation |

## pgTAP Test Scenarios

| # | Cenário | Asserção | INV |
|---|---------|----------|-----|
| T1 | INSERT com `organization_id` do JWT ativo | ✅ sucesso | INV-1 |
| T2 | SELECT filtrando por outro `organization_id` | ❌ 0 rows (RLS blocks) | INV-22 |
| T3 | INSERT com `target_entity = 'bus'` | ❌ CHECK violation (`chk_cmt_target_entity`) | INV-14 |
| T4 | INSERT duplicando `(org, entity, name)` | ❌ UNIQUE violation (`uq_cmt_org_entity_name`) | — |
| T5 | UPDATE incrementa `version` automaticamente | ✅ `version = OLD + 1`, `updated_at` refreshed | — |

## Structural Verification

- [x] Table uses `CREATE TABLE IF NOT EXISTS` (INV-DB: non-destructive)
- [x] All datetime columns use `TIMESTAMPTZ` (INV-6)
- [x] RLS enabled with JWT-based policy (INV-2)
- [x] No `auth.uid()` usage — only `auth.jwt() -> 'app_metadata' ->> 'org_id'`
- [x] CHECK constraint limits `target_entity` to `asset | contract | zone | operator`
- [x] UNIQUE constraint on `(organization_id, target_entity, name)`
- [x] Partial index on `is_default = TRUE` for fast default lookup
- [x] Version bump trigger with `CREATE OR REPLACE FUNCTION` (idempotent)
- [x] `DROP TRIGGER IF EXISTS` before `CREATE TRIGGER` (idempotent reapply)

## Column Mapping JSONB Contract

Each element in `column_mappings` JSONB array:

```json
{
  "csv_header": "PLACA",
  "target_field": "identifier",
  "transform": "uppercase",
  "required": true,
  "format_hint": null
}
```

Validated at the application layer via `ColumnMapping.fromJson()` (IntegrityException shield).
