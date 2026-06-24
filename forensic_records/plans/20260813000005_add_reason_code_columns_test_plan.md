# Plano de Testes — add_reason_code_columns

**Migração:** `supabase/migrations/20260813000005_add_reason_code_columns.sql`
**Teste pgTAP:** `supabase/tests/20260813000005_add_reason_code_columns_test.sql`
**Invariantes:** INV-1 (imutabilidade forense), INV-6 (`TIMESTAMPTZ` — N/A aqui,
colunas TEXT), INV-DB (ADD COLUMN nullable = zero-downtime; backfill em lotes).
**Risco:** Médio — costura a taxonomia fechada (`dispute_reason_codes`) ao ciclo
de disputa. Falha = código vertical-específico vaza, FK frouxa deixa entrar
código inexistente, ou backfill em UPDATE único trava a tabela.

## Objetivo

Adiciona 3 colunas estruturadas à `sanction_review_queue`:
`rejection_reason_code`, `resolution_reason_code`, `peer_review_reason_code` —
todas FK para `dispute_reason_codes(code)` (catálogo fechado, B6 agnóstico). H3:
backfill de linhas legadas (`rejection_reason` livre, sem código) é feito em
**loop de 1000 linhas** (`GET DIAGNOSTICS ... ROW_COUNT`, `EXIT WHEN 0`), nunca um
UPDATE ilimitado.

## Correção de fato no plano (linha 795-796)

O plano afirmava "sanction_review_queue has NO immutability trigger... verified
against 10.5". **Falso** — `prevent_srq_immutable_mutation`
(`trg_srq_no_immutable_update`, mig 20260406000001, estendido em 20260610000001 e
20260805000002) existe. Guarda **apenas** `organization_id`, `ledger_entry_id`,
`set_id`, `contract_id`, `verdict_evidence`, `created_at`, `vehicle_plate`,
`operator_name`. As novas colunas `*_reason_code` **não** estão no conjunto
guardado → o backfill (e as RPCs de resolução que as preenchem em UPDATE) passam.
Não estendemos o guard de propósito: as RPCs setam `reason_code` em UPDATE
(NULL→valor); inclui-las bloquearia a resolução. Comentário da migração reescrito
para refletir a realidade.

## Estratégia

Estrutural + comportamental, como `postgres` (superusuário) dentro de
`BEGIN/ROLLBACK`. RLS/isolamento da `sanction_review_queue` já coberto pela suíte
própria da tabela — aqui o foco é coluna, FK e interação com o trigger de
imutabilidade. Backfill verificado por simulação: insere linha legada
(`rejection_reason` setado, código NULL), roda a UPDATE com a mesma forma do loop
e confere o mapeamento para `LEGACY_UNCLASSIFIED`.

## Casos pgTAP (plan = 9)

**Estrutura**
1. Coluna `rejection_reason_code` existe.
2. Coluna `resolution_reason_code` existe.
3. Coluna `peer_review_reason_code` existe.

**Integridade FK (catálogo fechado → 23503)**
4. `rejection_reason_code` rejeita código inexistente → `23503`.
5. `resolution_reason_code` rejeita código inexistente → `23503`.
6. `peer_review_reason_code` rejeita código inexistente → `23503`.

**Aceitação / interação com trigger**
7. Código válido (`LEGACY_UNCLASSIFIED`) aceito no INSERT (`lives_ok`).
8. UPDATE setando `reason_code` pós-insert **não** bloqueado pelo trigger de
   imutabilidade (`lives_ok`) — prova caminho do backfill/RPC de resolução.

**Backfill H3**
9. Linha legada (`rejection_reason` livre, código NULL) → após UPDATE de backfill
   recebe `LEGACY_UNCLASSIFIED`.

## Notas

- FK alvo é `dispute_reason_codes(code)` (PK), criado na migração 004 — esta
  migração depende de 004 já aplicada (ordem por timestamp garante).
- Migração só adiciona colunas (DDL exposto à Data API muda) →
  `supabase/types.database.ts` regenerado e commitado junto.
- Sem grants novos: as colunas herdam os grants existentes da
  `sanction_review_queue`.
