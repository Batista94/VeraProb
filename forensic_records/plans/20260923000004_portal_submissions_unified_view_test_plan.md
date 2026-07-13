# Plano de Testes — 20260923000004_portal_submissions_unified_view

**Migração:** `supabase/migrations/20260923000004_portal_submissions_unified_view.sql`
**pgTAP:** `supabase/tests/20260923000004_portal_submissions_unified_view_test.sql`
**CIA:** C — security_invoker + kinds

## Escopo

1. View + `security_invoker=true` + coluna `submission_kind`.
2. Seed evidence + justification → 2 kinds.
3. Authenticated SELECT na view → `42501` (deny-all bases + invoker).
