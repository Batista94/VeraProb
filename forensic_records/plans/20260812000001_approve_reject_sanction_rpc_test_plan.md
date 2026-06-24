# Plano de Testes — approve_sanction / reject_sanction RPC

**Migração:** `supabase/migrations/20260812000001_approve_reject_sanction_rpc.sql`
**Teste pgTAP:** `supabase/tests/20260812000001_approve_reject_sanction_rpc_test.sql`
**Invariantes:** INV-1, INV-3, INV-10, INV-22, INV-26, INV-6, INV-15.
**Risco:** Alto — fluxo de veredito inicial (approve/reject) move concorrência e
atomicidade para o banco. Falha = corrupção de cadeia de custódia (duplo
`VERDICT_SEALED`/`VERDICT_REFUSED`) ou bypass de isolamento de tenant.

## Objetivo

Liquidar a dívida de atomicidade do veredito inicial: substituir a trilha
não-atômica em Dart (TOCTOU read → ledger append → queue update em round-trips
separados) por duas RPCs `SECURITY DEFINER` que executam, em UMA transação:
`lock (FOR UPDATE) → re-check de status pending → append no ledger → flip da
fila`. Fecha a corrida onde dois auditores julgando a mesma multa pendente
geram dois fatos no ledger.

## Casos pgTAP / SQL (plan = 21)

1. `has_function` — `approve_sanction(uuid,uuid,uuid,text,timestamptz)` existe.
2. `prosecdef` — `approve_sanction` é SECURITY DEFINER.
3. `has_function` — `reject_sanction(uuid,uuid,uuid,text,text,timestamptz)` existe.
4. `prosecdef` — `reject_sanction` é SECURITY DEFINER.
5–7. Grants approve: `authenticated` EXECUTE; `anon` e `service_role` SEM EXECUTE (Max hardening).
8–10. Grants reject: idem.
11. Happy approve: `pending → applied` (`lives_ok` sob JWT AUDITOR Org A).
12. Status da fila vira `applied`.
13. Exatamente UM fato `VERDICT_SEALED` para o queue entry (INV-3).
14. Idempotência: segundo approve na linha já `applied` → `P0001`
    (`IdempotencyProcessingException`), nenhum segundo fato.
15. Happy reject: `pending → rejected` (`lives_ok`).
16. Status da fila vira `rejected`.
17. Exatamente UM fato `VERDICT_REFUSED` (INV-3).
18. Reject com motivo vazio (`'    '`) → `42501` fail-closed (motivo obrigatório).
19. **Anti-spoof:** `p_reviewed_by_user_id` ≠ JWT `sub` → `42501`. O revisor é
    vinculado ao claim `sub`; cliente não pode atribuir veredito a outro usuário.
20. Cross-tenant (JWT Org B, alvo Org A) → `42501` (anti-oracle, INV-26).
21. Role OPERATOR → `42501` (RBAC server-side; só TENANT_ADMIN/AUDITOR).

## Concorrência real (multi-sessão)

pgTAP roda em sessão única — não prova paralelismo verdadeiro. A corrida real
(dois auditores distintos aprovando a MESMA penalidade pendente ao mesmo tempo)
é coberta por `test/integration/approve_sanction_concurrency_test.dart`, que
dispara dois `approve_sanction` autenticados via `Future.wait` contra o Supabase
local (duas sessões reais). Garante: o lock `FOR UPDATE` + re-check de status
serializa os aprovadores → exatamente **1** selo (`applied`) + **1**
`IdempotencyProcessingException`, **1** fato `VERDICT_SEALED`, `approved_by_user_id`
= o vencedor da corrida. O contrato usa threshold dual-control alto (`100000000`)
para o veredito selar TERMINAL e não bifurcar — isola o TOCTOU do quatro-olhos.
Auto-skip se o Supabase local não estiver up (espelha
`dual_control_confirm_concurrency_test.dart`).

## Notas

- A identidade do revisor vem do JWT `sub` e é casada contra `p_reviewed_by_user_id`
  (rejeita divergência). Isto é a fundação anti-fraude do dual-control (Pacote 2).
- Guarda primária de duplicidade = `FOR UPDATE` + re-check `status='pending'`.
  `applied`/`rejected` são terminais (SanctionTransitionGuard), logo nenhum
  segundo fato é possível após o flip. **Sem** índice único parcial (diverge do
  resolve_dispute): o arco `retract` permite re-julgar uma entrada, o que tornaria
  um índice `VERDICT_*` um falso-positivo `23505`. Decisão registrada no header
  da migração (deferido p/ Council).
- Payload do ledger espelha `SlaLedgerMapper._applied`/`._rejected` (INV-15 replay).
- A trilha Dart (`ApproveSanctionHandler`/`RejectSanctionHandler`) mantém as
  guardas client-side (tenant, RBAC, motivo, status) como fail-fast/anti-oracle;
  a barreira de concorrência é o row lock no DB.

## Estado esperado

`make test-db` PASS (21/21). `make test` PASS (handlers refatorados + PBT de
idempotência atualizado: approve/reject migrados para o mecanismo
`dbTransactionalRpc`, paralelo ao resolve_dispute). Scanner `[GO]`.
