# Plano de Teste — Financial Guard P4/6: Crédito de Reversão de Disputa

- **Migração:** `supabase/migrations/20260913000004_financial_guard_credit.sql`
- **pgTAP:** `supabase/tests/20260913000004_financial_guard_credit_test.sql`
- **Invariantes:** INV-3 (ledger intocado), INV-4 (BIGINT cents), INV-15 (mês lido de `cap_month_utc` selado — nunca re-clampado), INV-18 (`cap_reached_at_utc` nunca limpo), INV-22 (lookups org-bound)
- **Design:** `forensic_records/plans/20260704_financial_guard_architecture_plan.md` §2.4; decisão do usuário: `VERDICT_REFUSED` CREDITA

## Escopo

`credit_financial_guard()` — trigger AFTER INSERT `WHEN type IN ('DISPUTE_ACCEPTED','VERDICT_REFUSED')`. Cadeia: `payload.queue_entry_id` → `sanction_review_queue` → `ledger_entry_id` → sanção original → crédito = fine PÓS-CORTE, mês = `cap_month_utc` selado. Exactly-once via PK de `financial_guard_credits`. `queue_entry_id` AUSENTE = no-op fail-closed (sem crédito; seeds legados/sintéticos não quebram); queue dangling = `23000` fail-fast (#21); queue existe mas linha original do ledger ausente = no-op + evento `FINANCIAL_GUARD_DRIFT` (um RAISE no AFTER trigger tornaria a disputa irresolvível por anomalia de dados — crédito fail-closed, forense loud; fixtures commitadas de RPC seedam queue sem linha de ledger). Sem `lock_timeout` custom (RAISE no AFTER abortaria a própria resolução da disputa — serialização plena aceitável, evento raro).

## Casos

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 1 | Pré-condição: 2 sanções (30000+50000) sob cap 100000 | accrual = 80000 |
| 2-3 | (#11) `DISPUTE_ACCEPTED` da sanção de 50000 | accrual = 30000; credits row 50000 |
| 4-5 | (#20) 2º `DISPUTE_ACCEPTED` mesmo `queue_entry_id` | accrual inalterado; 1 credits row (exactly-once) |
| 6-7 | (#11) `VERDICT_REFUSED` da sanção de 30000 (decisão do usuário) | accrual = 0; credits row 30000 |
| 8-9 | `DISPUTE_OVERTURNED` NÃO credita (multa mantida) | accrual = 0 intacto; sem novo credits row |
| 10 | `DISPUTE_RETRACTED` NÃO credita | accrual intacto |
| 11-12 | Crédito de sanção TRUNCADA (original 30000, applied 20000, cap 20000) | credita 20000 (pós-corte), accrual = 0 |
| 13-15 | Gate guard-inativo: sanção de contrato sem cap | lives_ok; sem credits row; sem accrual |
| 16 | `queue_entry_id` ausente (seed sintético) | lives_ok no-op |
| 17 | (#21) `queue_entry_id` dangling | `23000` fail-fast |
| 18-19 | Floor-0: accrual reduzido manualmente p/ 10000, crédito 40000 | accrual clampado em 0 + evento `FINANCIAL_GUARD_DRIFT` |
| 20 | `cap_reached_at_utc` NUNCA limpo após crédito zerar accrual | ainda NOT NULL |
| 21-22 | Queue existe mas sanção original ausente do ledger | lives_ok (disputa não bloqueada) + `FINANCIAL_GUARD_DRIFT` |

## Invariantes Verificados

- **Exactly-once:** PK `(org, sanction_ledger_entry_id)` + `ON CONFLICT DO NOTHING` + gate `FOUND`.
- **INV-15:** mês do crédito = `cap_month_utc` do débito (byte-exato, sem re-clamp contra `now()` do crédito).
- **Semântica legal:** só anulação de multa credita (`DISPUTE_ACCEPTED`, `VERDICT_REFUSED`); `OVERTURNED`/`RETRACTED` mantêm a multa.
- **INV-18:** breach histórico permanece latched.

## Setup do Fixture

Org f4, contratos K1 (cap 100000), K2 (cap 20000), K3 (sem cap), K4 (cap 100000, drift). Sanções inseridas como `postgres` disparam o engine (P3) e o `trg_auto_enqueue_sanction` (queue rows automáticas — `ledger_entry_id` UNIQUE). Eventos de disputa referenciam `queue_entry_id` real via subquery.

## Verificação Manual

```bash
supabase db reset && make test-db
```
