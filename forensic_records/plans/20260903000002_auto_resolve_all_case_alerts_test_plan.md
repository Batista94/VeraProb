# Plano de Testes — auto_resolve_all_case_alerts (trigger expansion)

**Migração:** `supabase/migrations/20260903000002_auto_resolve_all_case_alerts.sql`
**Teste pgTAP:** `supabase/tests/20260903000002_auto_resolve_all_case_alerts_test.sql`
**Invariantes:** INV-1, INV-22, INV-6 (resolved_at_utc via NOW()).

## Objetivo

Fase 2 da correção do Centro de Comando. A fase 1 (20260903000001) criou o
trigger mas restringiu o matching a `alert_type = 'PENALTY_APPLIED'`. O
`AlertDerivationService` também cria `NO_SHOW` e `EVIDENCE_GAP` com a mesma
chave de caso (`entity_id=set_id`, `contract_id`). Esses tipos permaneciam ACTIVE
no drawer mesmo após sanção encerrada.

Solução: `CREATE OR REPLACE FUNCTION` expandindo WHERE para resolver TODOS os
tipos de alerta pela chave do caso, sem recriar o trigger.

## Casos pgTAP (plan = 5)

1. T0 — `has_function` — `auto_resolve_alerts_on_sanction_terminal` existe.
2. T1 — `pending → applied` → alerta `NO_SHOW` vira `RESOLVED`.
3. T2 — `pending → applied` → alerta `EVIDENCE_GAP` vira `RESOLVED`.
4. T3 — `pending → applied` → resolve `NO_SHOW` + `EVIDENCE_GAP` + `PENALTY_APPLIED` juntos (3 alertas, mesmo caso).
5. T4 — `pending → disputed` (não-terminal) → `NO_SHOW` permanece `ACTIVE`.

Cross-org (INV-22) e idempotência já cobertos em `20260903000001_test.sql`.

## Notas

- `CREATE OR REPLACE FUNCTION` substitui apenas o corpo da função; o trigger
  `trg_srq_resolve_alerts` permanece intacto — nenhum `DROP TRIGGER` necessário.
- Lógica `DISPUTE_DEFENSE_SUBMITTED` via `context->>'queue_entry_id'` preservada
  no OR branch (cobertura em 20260903000001 T3b e T8).
- Guard de idempotência `OLD.status IN terminal` inalterado — sem risk de
  double-resolve.

## Estado esperado

`make test-db` PASS (5/5 novos, total ~1401+). Scanner `[GO]`.
