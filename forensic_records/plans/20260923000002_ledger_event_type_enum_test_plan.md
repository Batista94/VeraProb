# Plano de Testes — 20260923000002_ledger_event_type_enum

**Migração:** `supabase/migrations/20260923000002_ledger_event_type_enum.sql`
**pgTAP:** `supabase/tests/20260923000002_ledger_event_type_enum_test.sql`
**CIA:** I — ENUM assignment + reject

## Escopo

1. Enum presente; CHECK removido; triggers/indexes recriados.
2. `pg_cast` text → `ledger_event_type` ASSIGNMENT.
3. INSERT via variável TEXT (`lives_ok`); tipo inválido → `22P02`.
