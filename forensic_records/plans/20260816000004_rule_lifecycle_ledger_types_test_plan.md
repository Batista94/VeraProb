# Test Plan: rule_lifecycle_ledger_types

## Migration

`20260816000004_rule_lifecycle_ledger_types.sql`

## Tests (supabase/tests/20260816000004_rule_lifecycle_ledger_types_test.sql — 7 asserts)

- Constraint keeps canonical name `chk_ledger_type` after the H1 widening
  (ADD `_v4` NOT VALID → VALIDATE → DROP old → RENAME; committed tests
  assert the canonical name).
- Intermediate `chk_ledger_type_v4` does not linger (rename completed).
- New Sprint B types accepted by real INSERTs (`lives_ok`): `RULE_SCHEDULED`,
  `RULE_ACTIVATED`, `RULE_RETIRED`, `CONTRACT_FINANCIAL_TERMS_AMENDED`.
- Unknown type → 23514 (CHECK validated and enforcing).
