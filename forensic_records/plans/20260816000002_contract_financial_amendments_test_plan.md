# Test Plan: contract_financial_amendments

## Migration
`20260816000002_contract_financial_amendments.sql`

## Tests
- UPDATE/DELETE in `contract_financial_amendments` -> blocked by trigger (INV-3)
- RLS org-scoped SELECT works
- explicit grants work for API roles
- INT penalty multiplier BPS constraint (>0)
