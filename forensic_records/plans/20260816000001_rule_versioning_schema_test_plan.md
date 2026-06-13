# Test Plan: rule_versioning_schema

## Migration

`20260816000001_rule_versioning_schema.sql`

## Council remediation notes (validated in review)

- Backfill added BEFORE the CHECK: pre-existing rows received
  `created_at_utc = NOW()` from the column DEFAULT while their
  `active_from_utc` is historical — without
  `SET created_at_utc = active_from_utc` the `VALIDATE CONSTRAINT` fails on
  any database with legacy rules AND every later UPDATE on those rows
  (closing/superseding) re-checks the CHECK and is blocked.

## Tests (supabase/tests/20260816000001_rule_versioning_schema_test.sql — 9 asserts)

- Columns `is_scheduled` (default false) and `created_at_utc` exist.
- Partial unique indexes `idx_unique_current_rule` and
  `idx_unique_scheduled_rule` exist; legacy `idx_unique_active_rule_type`
  dropped (1 current + 1 scheduled per type are independent states).
- Backdated direct INSERT (`active_from_utc` 10min before `created_at_utc`)
  → 23514 `chk_crv_no_backdate` (INV-15 defense in depth).
- Two scheduled rules of same type → 23505 `idx_unique_scheduled_rule`.
- Two current rules of same type → 23505 `idx_unique_current_rule`.

## Fixture convention (downstream impact)

Any seed/import inserting historical rules (`active_from_utc` in the past)
MUST declare a consistent `created_at_utc` (honest provenance) or
`chk_crv_no_backdate` rejects the row — fixed in
`test/infrastructure/sla_audit/postgres_forensic_evidence_snapshot_repository_test.dart`.
Applies to future bulk importers (Phase 10.10).
