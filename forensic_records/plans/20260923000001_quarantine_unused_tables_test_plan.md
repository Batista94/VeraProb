# Plano de Testes — 20260923000001_quarantine_unused_tables

**Migração:** `supabase/migrations/20260923000001_quarantine_unused_tables.sql`
**pgTAP:** `supabase/tests/20260923000001_quarantine_unused_tables_test.sql`
**CIA:** C — privilege catalog + runtime 42501
**Invariantes:** INV-1, INV-2, INV-22, INV-DATA-API-GRANT. INV-DB: apenas REVOKE de privilégio.

## Escopo

1. `REVOKE ALL` de `anon`/`authenticated` nas 6 tabelas (catalog asserts).
2. Runtime: `SET ROLE authenticated` + JWT → `throws_ok` SELECT/INSERT `42501`.
3. `service_role` `lives_ok` SELECT (ops path).
4. Sem `DROP TABLE` (INV-DB).
