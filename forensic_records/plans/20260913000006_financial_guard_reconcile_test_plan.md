# Plano de Teste — Financial Guard P6/6: Reconciliação (true-up + drift)

- **Migração:** `supabase/migrations/20260913000006_financial_guard_reconcile.sql`
- **pgTAP:** `supabase/tests/20260913000006_financial_guard_reconcile_test.sql`
- **Invariantes:** INV-4, INV-6, INV-15 (recompute idempotente; bucket selado `cap_month_utc` quando presente), INV-16 (varredura limitada a 2 meses, sem índice JSONB dedicado no ledger quente — knob futuro), INV-22, ordem de lock contracts → accrual
- **Design:** `forensic_records/plans/20260704_financial_guard_architecture_plan.md` §6.5

## Escopo

`reconcile_financial_guard(p_organization_id DEFAULT NULL)` — service_role-only (REVOKE PUBLIC + re-grant explícito de service_role). Para cada contrato com cap, mês corrente + anterior: `expected = Σ fine_cents aninhado (bucket = cap_month_utc selado, senão date_trunc(occurred_at) — cobre deferred e época capless) − Σ credits`. Divergência → correção sob lock de contracts + `FINANCIAL_GUARD_DRIFT` critical. pg_cron horário guardado (só Cloud, padrão `20260424000002`).

Viés conservador documentado: multas anuladas em época capless não têm credit marker → expected superconta (mais proteção ao pagador); DRIFT sinaliza p/ revisão humana, nunca corta silenciosamente.

## Casos

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 1-3 | Assinatura + grants (service_role SIM, authenticated NÃO) | ok |
| 4-7 | (#18) Multa não-contabilizada (passthrough capless + cap ativado direto — mesmo buraco contábil de uma linha deferred pós-55P03; `ALTER TABLE DISABLE TRIGGER` no pai particionado dentro de transação SEGFAULTA o PG local) + débito guardado | pré 20000; 1 correção; accrual 50000; DRIFT critical selado |
| 8-9 | 2ª execução | 0 correções; estado byte-idêntico (INV-15) |
| 10-11 | Accrual adulterado (99) | detectado e restaurado da verdade do ledger (50000) |
| 12-14 | Crédito de disputa entra na fórmula | accrual 30000 pós-crédito; reconcile concorda (0 correções, sem falso drift) |
| 15 | anon também sem EXECUTE (catálogo) | ok — asserção via `has_function_privilege`, não chamada viva: EXECUTE negado sob `SET ROLE` segfaulta o backend nesta imagem supabase local (signal 11, reproduzido com probe trivial — bug de ambiente) |

## Casos NÃO cobertos (delegados)

- Contenção real de lock (deferred genuíno por 55P03): impossível em sessão pgTAP única (dblink bloqueado). Fixture reproduz o mesmo estado contábil (multa penal sem accrual e sem `cap_month_utc`); paralelismo real fica p/ harness Dart de integração (P2, padrão 2 SupabaseClient + Future.wait já provado).
- Agendamento pg_cron: extensão inexistente no local dev (guard testado implicitamente pelo reset sem erro).

## Setup do Fixture

Org f6, contrato cap 100000. Débito guardado (20000, accrual real) + linha deferred (30000, `cap_check_deferred=true`, inserida com `trg_financial_guard` desabilitado e reabilitado em seguida). `DISPUTE_ACCEPTED` via queue do auto-enqueue.

## Verificação Manual

```bash
supabase db reset && make test-db
```
