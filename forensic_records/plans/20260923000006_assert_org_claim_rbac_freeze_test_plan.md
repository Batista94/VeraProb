# Plano de Testes — 20260923000006_assert_org_claim_rbac_freeze

**Migração:** `supabase/migrations/20260923000006_assert_org_claim_rbac_freeze.sql`
**pgTAP:** `supabase/tests/20260923000006_assert_org_claim_rbac_freeze_test.sql`
**CIA:** C+I — INV-1 / INV-22 / INV-26

## Escopo

1. Função existe; null JWT lives; freeze comment.
2. JWT org A + claim org B → `42501` / `not found`.
3. Match lives; `NULL` → `organization_id required`; `service_role` bypass.
