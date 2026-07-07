# Plano de Teste — Financial Guard P1/6: Colunas de Cap (Stop-Loss)

- **Migração:** `supabase/migrations/20260913000001_financial_guard_cap_columns.sql`
- **pgTAP:** `supabase/tests/20260913000001_financial_guard_cap_columns_test.sql`
- **Invariantes:** INV-4 (BIGINT cents), INV-3 (append-only de amendments intacto), INV-DB (CHECK via NOT VALID → VALIDATE, sem ALTER bloqueante)
- **Design:** `forensic_records/plans/20260704_financial_guard_architecture_plan.md` §1.1

## Escopo

Adição de `monthly_penalty_cap_cents BIGINT NULL` em `contracts` (valor vivo lido pelo trigger do guard) e em `contract_financial_amendments` (espelho versionado append-only). `NULL` = sem teto. CHECK `> 0` em ambas.

## Casos

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 1-3 | Coluna `contracts.monthly_penalty_cap_cents` existe, `bigint`, nullable | ok |
| 4-6 | Coluna `contract_financial_amendments.monthly_penalty_cap_cents` existe, `bigint`, nullable | ok |
| 7 | INSERT contrato com cap `NULL` | aceito (sem teto) |
| 8 | INSERT contrato com cap `500000` | aceito |
| 9 | INSERT contrato com cap `0` | rejeitado `23514` |
| 10 | INSERT contrato com cap `-1` | rejeitado `23514` |
| 11 | INSERT amendment com cap `500000` | aceito |
| 12 | INSERT amendment com cap `NULL` | aceito |
| 13 | INSERT amendment com cap `0` | rejeitado `23514` |
| 14 | UPDATE em amendment (regressão INV-3) | rejeitado `P0001` append-only |
| 15 | `chk_contracts_monthly_penalty_cap_positive` existe e `convalidated` | ok |
| 16 | `chk_cfa_monthly_penalty_cap_positive` existe e `convalidated` | ok |

## Invariantes Verificados

- **INV-4:** tipo `bigint` (cents), nunca numeric/float.
- **INV-3:** trigger `trg_cfa_append_only` continua bloqueando UPDATE após ALTER.
- **INV-DB:** constraints criadas `NOT VALID` e validadas em passo separado (casos 15-16 confirmam `convalidated = true`).

## Setup do Fixture

Org inline `f1000000-...-0001` + contratos inseridos por caso (como `postgres`, RLS não forçada). Amendment exige `amended_by_user_id UUID` e `penalty_multiplier_bps > 0`; `effective_at_utc = now()` satisfaz `chk_cfa_no_backdate`.

## Verificação Manual

```bash
supabase db reset && make test-db
```
