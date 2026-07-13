# Plano de Testes — 20260925000001_wire_assert_org_claim_execution_rpcs

**Migração:** `supabase/migrations/20260925000001_wire_assert_org_claim_execution_rpcs.sql`
**pgTAP:** `supabase/tests/20260925000001_wire_assert_org_claim_execution_rpcs_test.sql`
**CIA:** C+I — INV-1 / INV-22 / INV-26

## Escopo

1. Closer / complete / start_transit / compliance bodies call `assert_org_claim`.
2. JWT org A + closer(org B) → `42501` / `not found` before any close.
3. Null JWT (postgres) closer still lives for dwell-complete seed.
