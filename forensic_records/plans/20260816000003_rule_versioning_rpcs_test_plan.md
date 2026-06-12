# Test Plan: rule_versioning_rpcs

## Migration
`20260816000003_rule_versioning_rpcs.sql`

## Tests
- `update_contractual_rule` with `p_effective_at_utc` < 5 min past -> RAISE
- `schedule_contractual_rule` sets `is_scheduled=true`, enforces > NOW()
- `activate_scheduled_rule` is idempotente, closes current, activates scheduled
- `retire_contractual_rule` seals `active_to_utc` with no successor, emits `RULE_RETIRED`
- cross-org schedule/retire/amend -> 42501 (INV-26)
- grants using `has_function_privilege` for authenticated+service_role
