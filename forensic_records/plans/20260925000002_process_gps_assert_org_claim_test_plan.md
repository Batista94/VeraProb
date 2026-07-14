# Plano de Testes — 20260925000002_process_gps_assert_org_claim

**Migração:** `supabase/migrations/20260925000002_process_gps_assert_org_claim.sql`
**pgTAP:** `supabase/tests/20260925000002_process_gps_assert_org_claim_test.sql`
**CIA:** I — INV-1 / INV-3 SYSTEM_AUTO_START runtime on v2

## Escopo

1. `process_gps` body calls `assert_org_claim`.
2. Seed vehicle + planned execution inside origin zone → GPS call writes one SYSTEM_AUTO_START on v2, zero on v1.
