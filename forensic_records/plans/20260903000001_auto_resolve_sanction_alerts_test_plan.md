# Plano de Testes — auto_resolve_alerts_on_sanction_terminal (trigger)

**Migração:** `supabase/migrations/20260903000001_auto_resolve_sanction_alerts.sql`
**Teste pgTAP:** `supabase/tests/20260903000001_auto_resolve_sanction_alerts_test.sql`
**Invariantes:** INV-1, INV-22, INV-3 (preservação do ledger), INV-6 (resolved_at_utc via NOW()).

## Objetivo

Fechar o gap entre status terminal da `sanction_review_queue` e ciclo de vida dos
`operational_alerts` no Centro de Comando. Após qualquer das 7 ações do auditor
(approve, reject, resolveDispute, acknowledgeInternal, confirmPeer, declinePeer,
portal acknowledge) o alerta `PENALTY_APPLIED` e/ou `DISPUTE_DEFENSE_SUBMITTED`
correspondente deve sair do drawer automaticamente.

Solução: trigger AFTER UPDATE `SECURITY DEFINER` em `sanction_review_queue` que,
na primeira entrada no estado terminal, emite `UPDATE operational_alerts SET
status='RESOLVED'` na mesma transação. O `activeAlertsStreamProvider` subscreve
Realtime com filtro `status=eq.ACTIVE` — nenhuma mudança em Dart necessária.

Matching por tipo:
- `PENALTY_APPLIED` → `entity_id = NEW.set_id AND contract_id = NEW.contract_id`
- `DISPUTE_DEFENSE_SUBMITTED` → `context->>'queue_entry_id' = NEW.id::text`

Guard (evita re-fire em `applied → acknowledged`):
```sql
IF NEW.status NOT IN ('applied','rejected','acknowledged')
   OR OLD.status IN ('applied','rejected','acknowledged') THEN RETURN NEW; END IF;
```

## Casos pgTAP / SQL (plan = 11)

1. T0a — `has_function` — `auto_resolve_alerts_on_sanction_terminal()` existe.
2. T0b — trigger `trg_srq_resolve_alerts` existe em `sanction_review_queue`.
3. T1 — `pending → applied` → `PENALTY_APPLIED` alert vira `RESOLVED`.
4. T2 — `pending → rejected` → `PENALTY_APPLIED` alert vira `RESOLVED`.
5. T3a — `disputed → applied` → `PENALTY_APPLIED` alert vira `RESOLVED`.
6. T3b — `disputed → applied` → `DISPUTE_DEFENSE_SUBMITTED` alert vira `RESOLVED` (mesmo UPDATE batch).
7. T4 — `pending → acknowledged` → `PENALTY_APPLIED` alert vira `RESOLVED`.
8. T5 — `pending → disputed` (não-terminal) → alert permanece `ACTIVE`.
9. T6 — cross-org guard: Org A entry com `set-cross/ctr-cross` não resolve alert de Org B com mesmos valores (INV-22).
10. T7 — idempotência: entry já em `applied` re-atualizado para `applied` → guard retorna cedo → alert permanece `ACTIVE`.
11. T8 — `DISPUTE_DEFENSE_SUBMITTED` isolado (sem `PENALTY_APPLIED`): apenas o alert de disputa é resolvido.

## Notas

- `SECURITY DEFINER` necessário: RLS em `operational_alerts` bloquearia o UPDATE
  disparado pelo trigger (que roda como o usuário que atualizou a fila, não como
  `postgres`). A função corre como seu owner (postgres/service_role) que tem
  `BYPASSRLS`.
- Idempotência garantida pelo guard `OLD.status IN terminal` — evita que
  `applied → acknowledged` (segunda transição terminal) tente resolver alertas
  já em `RESOLVED` (query inocente) ou, pior, resolva alertas de uma entrada
  diferente que acabou de passar para o mesmo `set_id/contract_id`.
- Nenhuma migração de dados necessária: alertas já `RESOLVED` ou `ACKNOWLEDGED`
  não são tocados (filtro `status='ACTIVE'`).
- Dart: zero alterações. `activeAlertsStreamProvider` filtra `status=eq.ACTIVE`
  via Realtime; o trigger resolve no DB, Realtime emite evento de UPDATE, drawer
  remove a linha automaticamente.

## Estado esperado

`make test-db` PASS (11/11 novos). Scanner `[GO]`.
