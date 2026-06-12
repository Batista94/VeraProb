# Test Plan: rule_lifecycle_ledger_types

## Migration
`20260816000004_rule_lifecycle_ledger_types.sql`

## Tests
- `chk_ledger_type` includes `RULE_SCHEDULED`, `RULE_ACTIVATED`, `RULE_RETIRED`, `CONTRACT_FINANCIAL_TERMS_AMENDED`
- Name of constraint remains canonical after widening
