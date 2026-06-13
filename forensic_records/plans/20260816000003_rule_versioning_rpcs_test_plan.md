# Test Plan: rule_versioning_rpcs

## Migration
`20260816000003_rule_versioning_rpcs.sql`

## Council remediation notes (validated in review)

- Ledger inserts use the canonical v2 contract `(organization_id, type,
  operator_id, set_id, contract_id, plan_version, payload, occurred_at_utc)` —
  `set_id` is NOT NULL and `contract_id` is UUID (original draft omitted
  `set_id` and cast to TEXT → runtime failure).
- `retire_contractual_rule` validates org ownership BEFORE any write
  (INV-22: no transient cross-org mutation) with `FOR UPDATE` lock.
- `activate_scheduled_rule` enforces TENANT_ADMIN (parity with siblings).
- `amend_contract_financial_terms` denormalizes into the REAL contracts
  columns: `financial_ceiling_cents` (BIGINT) + `penalty_multiplier`
  (legacy DOUBLE = bps/10000.0; bps INT is canonical, INV-4).
- `update_contractual_rule` keeps param name `p_now_utc` (CREATE OR REPLACE
  cannot rename); Dart caller passes `p_now_utc` (PostgREST named resolution).
  Added far-future guard: immediate updates must use schedule RPC.

## Tests (supabase/tests/20260816000003_rule_versioning_rpcs_test.sql — 35 asserts)

- Signatures: 5× `has_function`.
- `update_contractual_rule`: happy path returns UUID + row is current;
  backdate >5min → RAISE (INV-15); future date → RAISE (use schedule).
- `schedule_contractual_rule`: happy path `is_scheduled=true` without closing
  current; `RULE_SCHEDULED` ledger fact sealed; past date → RAISE; duplicate
  scheduled per type → 23505 (`idx_unique_scheduled_rule`).
- `activate_scheduled_rule`: promotes scheduled → current; closes previous
  current (history preserved, INV-3); `RULE_ACTIVATED` fact; idempotent re-call.
- `retire_contractual_rule`: seals `active_to_utc` with no successor;
  `RULE_RETIRED` fact; re-retire → RAISE.
- Cross-org (INV-22/26): Org B retire on Org A rule → same not-found message
  (anti-oracle) AND Org A row verified untouched (validate-before-write);
  Org B schedule on Org A contract → RAISE.
- RBAC: OPERATOR → 'TENANT_ADMIN role required'.
- `amend_contract_financial_terms`: happy path (amendment row append-only,
  author sealed, bps INT); contracts denorm synced (ceiling + multiplier
  15000bps = 1.5); `CONTRACT_FINANCIAL_TERMS_AMENDED` fact; backdate → RAISE;
  bps ≤ 0 → RAISE; cross-org → RAISE.
