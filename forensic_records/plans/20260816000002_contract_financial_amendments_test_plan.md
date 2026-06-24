# Test Plan: contract_financial_amendments

## Migration

`20260816000002_contract_financial_amendments.sql`

## Council remediation notes (validated in review)

- `penalty_multiplier_bps` and `amended_by_user_id` hardened to NOT NULL;
  `id` gained `DEFAULT gen_random_uuid()`.
- Grants reduced to least privilege: authenticated = SELECT only (writes go
  exclusively through the SECURITY DEFINER RPC); service_role explicit ALL
  (lesson: REVOKE FROM PUBLIC silently strips service_role).
- Index `idx_cfa_org_contract (organization_id, contract_id,
  effective_at_utc DESC)` for the amendment timeline read path.

## Tests (supabase/tests/20260816000002_contract_financial_amendments_test.sql — 12 asserts)

- Structure: table, `penalty_multiplier_bps` INT (INV-4),
  `financial_ceiling_cents` BIGINT, append-only trigger present.
- Grants: authenticated SELECT-only; service_role ALL (`table_privs_are`).
- Append-only (INV-3): UPDATE and DELETE both raise
  'INV-3: contract_financial_amendments is append-only'.
- Data constraints: retroactive `effective_at_utc` → 23514
  `chk_cfa_no_backdate` (INV-15); negative bps → 23514
  `chk_cfa_penalty_multiplier`.
- RLS (INV-22): Org A sees own amendment; Org B sees 0 rows.
