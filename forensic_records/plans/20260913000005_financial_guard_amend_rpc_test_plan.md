# Plano de Teste — Financial Guard P5/6: amend_contract_financial_terms v2

- **Migração:** `supabase/migrations/20260913000005_financial_guard_amend_rpc.sql`
- **pgTAP:** `supabase/tests/20260913000005_financial_guard_amend_rpc_test.sql` (+ atualização de assinatura no commitado `supabase/tests/20260816000003_rule_versioning_rpcs_test.sql`)
- **Invariantes:** INV-3 (amendments append-only), INV-4 (BIGINT cents), INV-15 (anti-backdating preservado), INV-22 (org do JWT)
- **Design:** `forensic_records/plans/20260704_financial_guard_architecture_plan.md` §5, §6-A

## Escopo

DROP da assinatura 5-arg + CREATE 6-arg (`p_monthly_penalty_cap_cents BIGINT DEFAULT NULL`, mesmos nomes/ordem — PGRST202-safe; overload único — PGRST300-safe). Corpo = última definição (20260816000003) + validação cap>0 + espelho no amendments + denorm em contracts + payload do ledger + **seed anti-headroom-fantasma**: transição NULL→valor upserta accrual do mês corrente com Σ multas do mês − Σ créditos já concedidos (contracts `FOR UPDATE` — serializa com o engine, mesma ordem de lock). Testes commitados 5-arg atualizados no mesmo pacote (chamadas posicionais 5-arg continuam válidas via DEFAULT).

## Casos

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 1-4 | Assinatura 6-arg, grants authenticated/service_role, overload único | ok |
| 5-8 | Amend com cap: retorna UUID; espelho no amendments; denorm em contracts; fato no ledger com cap | ok |
| 9-10 | Seed NULL→valor com multas pré-existentes no mês (30000+20000) | accrual = 50000, snapshot = 100000 |
| 11 | Cap removido via NULL explícito | contracts cap NULL |
| 12-13 | Ciclo de época (valor→NULL→valor) com crédito de disputa no meio | re-seed = 40000 − 40000 = 0; snapshot = 200000 (sem dupla contagem) |
| 14-16 | Chamada legada 5-arg | lives_ok; cap NULL; sem seed |
| 17-21 | (#14) Redução mid-month abaixo do acumulado (100000→30000 com accrued 60000) | cap vivo 30000; snapshot mid-month 100000 preservado; accrued intacto; próxima multa applied=0 + truncada |
| 22 | cap = 0 | `P0001` (sem teto = NULL, nunca 0) |

## Invariantes Verificados

- **PGRST202/PGRST300:** nomes de parâmetro preservados + DEFAULT no novo + overload antigo dropado.
- **Anti-headroom-fantasma:** ativar cap mid-month pré-consome as multas do mês (design §5 aplicado no momento em que o gap nasce).
- **Sem dupla contagem:** re-seed subtrai `financial_guard_credits` (multas anuladas em época capless sem marker → superconta conservadora, sinalizada pela reconciliação P6).
- **#14:** `cap_cents_snapshot` é histórico do bucket; o engine lê o cap VIVO de contracts (redução prospectiva imediata).

## Setup do Fixture

Org f5 + 4 contratos (pré-multas / ciclo de época / 5-arg legado / redução mid-month). Claims `TENANT_ADMIN` via `SET LOCAL request.jwt.claims` reaplicadas antes de cada chamada RPC (RESET ROLE entre blocos); sanções inseridas como `postgres` (engine P3 + auto-enqueue P4 ativos).

## Verificação Manual

```bash
supabase db reset && make test-db
```
