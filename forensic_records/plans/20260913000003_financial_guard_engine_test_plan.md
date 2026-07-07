# Plano de Teste — Financial Guard P3/6: Core Engine (trigger BEFORE INSERT)

- **Migração:** `supabase/migrations/20260913000003_financial_guard_engine.sql`
- **pgTAP:** `supabase/tests/20260913000003_financial_guard_engine_test.sql`
- **Invariantes:** INV-3, INV-4, INV-6, INV-15 (`cap_month_utc` selado no débito), INV-16 (lock_timeout + caminho deferred), INV-18 (guard corta a MULTA, nunca o fato), INV-22 (claim check antes de lock)
- **Design:** `forensic_records/plans/20260704_financial_guard_architecture_plan.md` §2, §3, §4

## Escopo

`chk_ledger_type` v7 (55 tipos v6 + `FINANCIAL_CAP_REACHED`/`FINANCIAL_CAP_WARNING`, swap NOT VALID → VALIDATE → DROP → RENAME de volta ao nome canônico) + `enforce_financial_guard()` (BEFORE INSERT, WHEN penal) + backfill bootstrap idempotente.

## Casos (numeração do design §4 entre parênteses)

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 1-2 | (#1) Contrato sem cap, payload limpo | payload byte-exato intocado; zero linhas de accrual |
| 3 | Chaves guard forjadas com cap NULL | stripped (sem trilha falsa) |
| 4-9 | (#2) Multa 30000 sob cap 100000 | applied=original, `cap_truncated=false`, `original_fine_cents`, `cap_remaining_before_cents=100000`, `cap_month_utc`=mês corrente, accrual=30000 |
| 10-13 | Warning 80% (accrued 80000) | `warned_at_utc` set; audit `FINANCIAL_CAP_WARNING` (warning/SYSTEM) 1×; linha ledger companheira 1× |
| 14-22 | (#3) Corte parcial (30000 com remaining 20000) | fine aninhado=20000, `cap_truncated=true`, original preservado (INV-18), accrual satura em 100000, breach latched, audit `FINANCIAL_CAP_REACHED` (critical) 1× com `breaching_ledger_entry_id` |
| 23-26 | (#4) Pós-limite (fine 10000) | applied=0, accrual inalterado, SEM segundo evento breach |
| 27-29 | (#5) Borda exata (50000 == cap 50000) | não truncado, breach latched, evento emitido |
| 30 | (#12) Warning idempotente | 1 evento após 2 inserts acima de 80% |
| 31-35 | (#15) Anti-forgery com cap ativo | todas as 5 chaves guard sobrescritas incondicionalmente |
| 36-40 | (#17) Clock-spoof ±90 dias (tol 300s) | `occurred_at_utc` forense NUNCA alterado; bucket clampado p/ `now()±tol`; soma acumulada correta |
| 41-43 | (#6) Independência mensal (org tol 100 dias) | multa de 35 dias atrás no bucket do mês real; mês corrente independente; 2 buckets |
| 44 | (#8) Multa sem `contract_id` | `23000` integrity_constraint_violation |
| 45 | `fine_cents` malformado ("abc") | `23000` tipado (nunca 22P02 cru) |
| 46 | Contrato de outra org | `23000` |
| 47-51 | (#16) 4 orgs → p0..p3 via `tableoid` | guard dispara nas 4 partições; accrual isolado por org |
| 52-54 | (#19) Wiring: trigger no pai + 4 partições, BEFORE, ordem alfabética após envelope | ok |
| 55 | (#13) `chk_ledger_type` canônico validado com 57 valores | ok (checagem textual do constraint — INSERTs dos 55 tipos legados dispararia fan-out de webhook/queue; regressão real coberta pela suite completa no reset) |
| 56 | (#7b) Claim mismatch tenant B → linha tenant A | `42501` antes de qualquer lock (ÚLTIMO teste do arquivo: `SET LOCAL request.jwt.claims` persiste até ROLLBACK) |

## Casos NÃO cobertos aqui (delegados)

- **Caminho deferred (55P03):** contenção real de lock é impossível em sessão pgTAP única (dblink bloqueado no supabase local). Fixture deferred + true-up testados na migração 6 (`reconcile_financial_guard`); paralelismo real fica p/ harness Dart de integração (P2).
- **Crédito de disputa:** migração 4.

## Invariantes Verificados

- **INV-18:** linha forense sempre inserida; `original_fine_cents` selado; `occurred_at_utc` jamais mutado.
- **INV-15:** `cap_month_utc` determinístico (clamp usa `now()` transacional — replay byte-exato).
- **INV-22:** claim `app_metadata.org_id` validado ANTES de lock (42501).
- **INV-16:** `lock_timeout` salvo/restaurado via `set_config(..., true)` — não vaza p/ a transação chamadora.

## Setup do Fixture

6 orgs (2 funcionais + 4 escolhidas por `satisfies_hash_partition` p/ cobrir p0..p3: `f3000000-…-03`→p0, `…-07`→p1, `…-0f`→p2, `…-01`→p3), 11 contratos com caps variados, inserts como `postgres` (claim check pula sem JWT). Org B com `clock_drift_tolerance_s = 8640000` (100 dias) p/ testar bucket de mês passado dentro da tolerância.

## Verificação Manual

```bash
supabase db reset && make test-db
```
