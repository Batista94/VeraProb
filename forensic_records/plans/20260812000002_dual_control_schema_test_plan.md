# Plano de Testes — Dual-Control Schema

**Migração:** `supabase/migrations/20260812000002_dual_control_schema.sql`
**Teste pgTAP:** `supabase/tests/20260812000002_dual_control_schema_test.sql`
**Invariantes:** INV-DB (zero-downtime), INV-4 (BIGINT cents), INV-6 (TIMESTAMPTZ).
**Risco:** Médio — schema aditivo. Falha = a state-machine de quatro-olhos não tem
onde gravar o threshold, o status intermediário ou os fatos de ciclo do peer review.

## Objetivo

Garantir que o modelo de dados do dual-control existe e é um superset estrito:
threshold (org + override por contrato), TTL, status `pending_peer_review`, colunas
de controle do peer review e os novos tipos de fato no ledger — sem invalidar
nenhuma linha histórica.

## Casos pgTAP (plan = 12)

1. `organizations.dual_control_threshold_cents` existe (BIGINT, nullable = OFF).
2. `organizations.dual_control_ttl_hours` existe com default 48.
3. `contracts.dual_control_threshold_cents` existe (override; NULL = herda).
4. `sanction_review_queue.first_reviewer_id` existe.
5. `sanction_review_queue.peer_review_proposed_action` existe.
6. `sanction_review_queue.peer_review_origin_status` existe.
7. `sanction_review_queue.peer_review_expires_at` existe (TIMESTAMPTZ).
8. `chk_srq_status` admite `pending_peer_review` (def contém o token).
9. `chk_srq_peer_action` restringe a ação proposta ao domínio esperado.
10. `chk_ledger_type` admite `PEER_REVIEW_REQUESTED`.
11. `chk_ledger_type` admite `PEER_REVIEW_DECLINED`.
12. `chk_ledger_type` admite `PEER_REVIEW_EXPIRED`.

## Notas

- pgTAP local não tem o overload schema-qualified de `col_is_nullable`; usamos
  `information_schema.columns` + `ok()` (padrão do 20260729000001).
- CHECK widening verificado por `pg_get_constraintdef` (texto contém o token),
  não por inserção — o INSERT exige seeds NOT NULL extensos.
