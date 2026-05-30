# Test Plan — Migration `20260730000001_contracts_natural_key.sql`

**Migration:** `20260730000001_contracts_natural_key.sql`
**Owner:** Council (Architect + Senior Engineer + QA/Security)
**Date:** 2026-07-30
**Status:** Pending Council sign-off

---

## Reason

Bloco 1D idempotent batch upsert keys on `(organization_id, external_id)`. Contract
rows imported without an `external_id` need a deterministic `ON CONFLICT` fallback.
The `contracts` table lacked any natural-key unique constraint (unlike
vehicles/drivers/contractors/zones). A contract is uniquely identified within a
tenant by `name + valid_from_utc`.

---

## Invariants at Play

| INV | Assertion |
|-----|-----------|
| INV-1 / INV-22 | `organization_id` leads the unique key — no cross-tenant collision |
| INV-3 | Append-only respected — no DROP/DELETE in migration |
| INV-DB | Non-blocking `CREATE UNIQUE INDEX` (not blocking `ALTER ... ADD CONSTRAINT`) |

---

## QA/Security — Exploit Path Closed

**Potential Exploit:** Without `organization_id` in the key, Tenant B importing a
contract named identically to Tenant A's (same `valid_from_utc`) could collide and
overwrite cross-tenant data.
**Closure:** Key is `(organization_id, name, valid_from_utc)` — unique per tenant,
never globally.

---

## Automated DB Tests (pgTAP)

File: `supabase/tests/20260730000001_contracts_natural_key_test.sql` — `plan(5)`:

1. Index `uq_contracts_org_name_validfrom` exists on `public.contracts`.
2. Index is `UNIQUE`.
3a. Index leads with `organization_id`.
3b. Index covers `name`.
3c. Index covers `valid_from_utc`.

Live conflict (`23505`) and idempotent re-run are asserted in the RPC test
(`20260730000002_csv_batch_upsert_rpcs_test.sql`) where an org + JWT context exists.

---

## Rollback Plan

> [!CAUTION]
> Rollback: `DROP INDEX IF EXISTS public.uq_contracts_org_name_validfrom;`
> Non-blocking, no data dependency. Safe before first production CSV contract
> import that relies on the natural-key fallback.

---

## Manual Verification Checklist

- [ ] `make test-db` passes with new pgTAP test
- [ ] `supabase db diff` shows 1 new index, no unexpected drops
- [ ] No existing contract rows violate the new uniqueness (migration would fail if dups exist)
