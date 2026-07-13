# Plano de Testes — 20260923000003_ledger_ssot_closer_v2

**Migração:** `supabase/migrations/20260923000003_ledger_ssot_closer_v2.sql`
**pgTAP:** `supabase/tests/20260923000003_ledger_ssot_closer_v2_test.sql`
**CIA:** I — closer SSOT (INV-3)

## Escopo

1. `pg_get_functiondef` referencia v2; sem INSERT em v1.
2. Seed mínimo (org/zone/CSE/execution dwell≥300s) + RPC closer.
3. `SYSTEM_AUTO_CLOSE` count = 1 em v2; = 0 em v1.
