# Plano de Teste — SLA Sandbox Schema (Phase 10.8)

- **Migração:** `supabase/migrations/20261001000001_sandbox_simulation_schema.sql`
- **pgTAP:** `supabase/tests/20261001000001_sandbox_simulation_schema_test.sql`
- **Invariantes:** INV-1, INV-2, INV-3, INV-4, INV-6, INV-22, INV-DATA-API-GRANT

## Escopo

Tabelas `sandbox_simulation_sessions` e `sandbox_simulation_results`: estrutura, RLS, imutabilidade, grants.

## Casos

| # | Caso | Resultado esperado |
|---|------|---------------------|
| 1-2 | Tabelas existem | `has_table` ok |
| 3-6 | Colunas obrigatórias existem (org_id, contract_id, etc.) | `has_column` ok |
| 7-8 | RLS habilitado em ambas tabelas | `is` RLS enabled |
| 9-10 | CHECK: `chk_sandbox_period` rejeita end <= start | `23514` |
| 11-12 | CHECK: `chk_sandbox_max_period` rejeita > 6 meses | `23514` |
| 13-14 | Imutabilidade: UPDATE bloqueado em sessions | `42501` |
| 15-16 | Imutabilidade: DELETE bloqueado em sessions (sem GUC) | `42501` |
| 17-18 | GC bypass: DELETE permitido com `app.gc_sandbox = true` | ok |
| 19-20 | RLS: Tenant A não vê sessões de Tenant B | 0 rows |
| 21-22 | Grants: authenticated pode SELECT + INSERT | ok |
| 23-24 | Grants: authenticated NÃO pode UPDATE/DELETE | denied |

## Verificação Manual

```bash
supabase db reset && make test-db
```
