# Test Plan: rule_versioning_schema

## Migration
`20260816000001_rule_versioning_schema.sql`

## Tests
- backdating INSERT direto -> CHECK `chk_crv_no_backdate` blocks
- 2 agendadas mesmo tipo -> `idx_unique_scheduled_rule` unique violation
- verifies `is_scheduled` and `created_at_utc` defaults
