# Plano de Testes — 20260923000005_notification_outbox_unified_view

**Migração:** `supabase/migrations/20260923000005_notification_outbox_unified_view.sql`
**pgTAP:** `supabase/tests/20260923000005_notification_outbox_unified_view_test.sql`
**CIA:** C — security_invoker + channel isolation

## Escopo

1. View + `security_invoker=true` + coluna `channel`.
2. Seed webhook + carrier → `channel IN ('webhook','email')`.
3. Authenticated org A vê 2; org B = 0 (INV-22).
