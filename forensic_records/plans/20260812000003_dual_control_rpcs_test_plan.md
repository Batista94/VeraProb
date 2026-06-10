# Plano de Testes — Dual-Control RPCs (Quatro-Olhos)

**Migração:** `supabase/migrations/20260812000003_dual_control_rpcs.sql`
**Teste pgTAP:** `supabase/tests/20260812000003_dual_control_rpcs_test.sql`
**Invariantes:** INV-1, INV-3, INV-10, INV-15, INV-21, INV-22, INV-26.
**Risco:** Crítico — núcleo anti-fraude. Falha = um único auditor consegue
aplicar/anular sozinho uma penalidade de alto valor (conluio interno).

## Objetivo

Provar a garantia matemática `reviewer2 != reviewer1` e o ciclo completo de
quatro-olhos: fork por threshold (org + override de contrato), confirmação por um
segundo auditor distinto, recusa (decline) e expiração (TTL).

## Casos pgTAP (plan = 34)

**Happy path + fork**
1–4. Existência/SECURITY DEFINER de `confirm_peer_review`, `decline_peer_review`,
   `expire_stale_peer_reviews`.
5–8. Grants (Max hardening): `confirm` só `authenticated` (anon não);
   `expire` só `service_role` (authenticated não — é job agendado, ator SYSTEM).
9–12. **Fork por threshold:** approve de multa > threshold NÃO sela — vira
   `pending_peer_review`, grava `first_reviewer_id` (do JWT `sub`) e exatamente
   um fato `PEER_REVIEW_REQUESTED` (nenhum `VERDICT_SEALED` ainda, INV-3).
13. Abaixo do threshold → caminho terminal direto (`applied`), sem fork.
14. **Override de contrato** (`COALESCE(contract, org)`): contrato 10000 faz uma
   multa de 50000 entrar em quatro-olhos mesmo com baseline org de 100000.
14b. **Reject fork (direção WAIVE):** `reject_sanction` de multa > threshold também
   bifurca (`peer_review_proposed_action='REJECT'`) — cobre o vetor de conluio por
   anulação injusta, não só aprovação.
15. **★ SELF-APPROVAL BLOQUEADO:** o requisitante (`sub` = `first_reviewer_id`)
   tentando confirmar → `P0001` (`DualControlSelfApprovalException`). Núcleo.

**Adverso / segurança (chamada direta à RPC — fora dos guards Dart)**
A1. **Cross-tenant confirm** (auditor de outra org) → `42501` (INV-22).
A2. **Cross-tenant decline** → `42501` (paridade).
A3. **NULL-JWT** (sem `app_metadata.org_id`) → `42501` (fail-closed, INV-1).
A4. **Role errada** (`OPERATOR` confirma) → `42501` (RBAC na RPC, não só UI).
A5. **Not-found** (auditor válido, id inexistente) → MESMO `42501` que wrong-org
   (anti-oráculo, INV-26).
A6. **Idempotência:** segundo confirm em item já terminal → `P0001`
   (`IdempotencyProcessingException`).

**Caminho terminal + ciclo**
16–18. **Segundo auditor distinto** confirma `APPROVE` → terminal `applied`; o fato
   carrega **as duas assinaturas** (`first_reviewer_id` + `second_reviewer_id`).
18b. **Confirm de REJECT fork** (e5) por 2º distinto → `rejected` + `VERDICT_REFUSED`
   com as duas assinaturas (caminho não-APPROVE).
19. **Decline** reverte ao status de origem (`pending`) + `PEER_REVIEW_DECLINED`.
20. **Expiry** (`expire_stale_peer_reviews`, ator SYSTEM, sem JWT): item vencido
   volta à origem + fato `PEER_REVIEW_EXPIRED`.

## Concorrência real (multi-sessão)

pgTAP roda em sessão única — não prova paralelismo verdadeiro. A corrida real
(dois confirmadores distintos selando o MESMO veredito bifurcado ao mesmo tempo)
é coberta por `test/integration/dual_control_confirm_concurrency_test.dart`, que
dispara dois `confirm_peer_review` autenticados via `Future.wait` contra o
Supabase local (duas sessões reais). Garante: o lock `FOR UPDATE` + re-check de
status serializa os confirmadores → exatamente **1** selo (`applied`) + **1**
`IdempotencyProcessingException`, **1** fato `VERDICT_SEALED`, assinatura dupla,
e `second_reviewer_id != first_reviewer_id`. Auto-skip se o Supabase local não
estiver up (espelha `resolve_dispute_concurrency_test.dart`).

## Notas

- `first_reviewer_id` e a identidade do confirmador vêm do JWT `sub` (server-side);
  nenhum param de cliente pode forjá-los. Mesma pessoa ⇒ mesmo `sub` ⇒ bloqueio.
- `fine_cents` é lido do `verdict_evidence` selado na linha (INV-15): mudar o
  threshold entre request e confirm não altera um veredito em andamento.
- O índice único parcial `uq_ledger_resolution_pN` (do resolve_dispute) continua
  garantindo um único fato `DISPUTE_*` por entrada quando o confirm é de origem
  disputa (OVERTURN/DISPUTE_ACCEPT).
- approve/reject/resolve_dispute são `CREATE OR REPLACE` (nova migração; arquivos
  merged intactos) — apenas adicionam o branch de threshold antes do terminal.
