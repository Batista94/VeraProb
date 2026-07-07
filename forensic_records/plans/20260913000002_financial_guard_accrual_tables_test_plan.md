# Plano de Teste — Financial Guard P2/6: Acumulador O(1) + Marcador de Crédito

- **Migração:** `supabase/migrations/20260913000002_financial_guard_accrual_tables.sql`
- **pgTAP:** `supabase/tests/20260913000002_financial_guard_accrual_tables_test.sql`
- **Invariantes:** INV-2/INV-22 (RLS org via `app_metadata.org_id`, SELECT-only), INV-4 (BIGINT cents), INV-6 (TIMESTAMPTZ), INV-DATA-API-GRANT
- **Design:** `forensic_records/plans/20260704_financial_guard_architecture_plan.md` §1.2, §1.2.1

## Escopo

`contract_penalty_monthly_accrual` (PK org+contract+mês, acumulador O(1) sob lock do contrato — LOCK ORDER INVARIANT documentado em `COMMENT ON TABLE`) e `financial_guard_credits` (exactly-once, PK org+sanction_ledger_entry_id). Ambas RLS SELECT-only; escrita só via triggers SECURITY DEFINER (migrações 3-4).

## Casos

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 1-4 | Tabelas existem com PK composta | ok |
| 5-10 | Grants exatos: authenticated={SELECT}, anon={}, service_role={7 privilégios} ×2 tabelas | ok |
| 11-12 | RLS habilitada nas 2 tabelas | ok |
| 13 | `accrued_cents < 0` | rejeitado `23514` |
| 14 | `cap_cents_snapshot = 0` | rejeitado `23514` |
| 15 | Tenant A vê própria linha de accrual (claims `app_metadata.org_id`) | 1 linha |
| 16 | Tenant B não vê linha de A (cenário #7a design §4) | 0 linhas |
| 17 | UPDATE como authenticated | negado `42501` |
| 18 | DELETE como authenticated | negado `42501` |
| 19 | Tenant A vê própria linha de credits | 1 linha |
| 20 | Tenant B não vê credits de A | 0 linhas |

## Invariantes Verificados

- **INV-2/INV-22:** policy usa `auth.jwt() -> 'app_metadata' ->> 'org_id'` (nunca claim legado top-level); isolamento cross-tenant testado nas duas tabelas.
- **INV-DATA-API-GRANT:** `table_privs_are` exato por role; REVOKE PUBLIC + re-grant explícito de service_role.
- **INV-4/INV-6:** BIGINT cents; `TIMESTAMPTZ` em todas as colunas temporais (exceto `month_utc DATE` — bucket de calendário UTC, não instante).

## Setup do Fixture

Orgs A/B inline, contrato de A, linha de accrual e de credits de A inseridas como `postgres` (bypass RLS). Claims: `SET LOCAL request.jwt.claims` com `app_metadata.org_id` + `SET LOCAL ROLE authenticated` / `RESET ROLE`.

## Verificação Manual

```bash
supabase db reset && make test-db
```
