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

## Casos pgTAP (plan = 23)

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
15. **★ SELF-APPROVAL BLOQUEADO:** o requisitante (`sub` = `first_reviewer_id`)
   tentando confirmar → `P0001` (`DualControlSelfApprovalException`). Núcleo.
16–18. **Segundo auditor distinto** confirma → terminal `applied`; o fato terminal
   carrega **as duas assinaturas** (`first_reviewer_id` + `second_reviewer_id`).
19. **Decline** reverte ao status de origem (`pending`) + `PEER_REVIEW_DECLINED`.
20. **Expiry** (`expire_stale_peer_reviews`, ator SYSTEM, sem JWT): item vencido
   volta à origem + fato `PEER_REVIEW_EXPIRED`.

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
