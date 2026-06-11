# Plano de Testes — dispute_sla_timer

**Migração:** `supabase/migrations/20260813000007_dispute_sla_timer.sql`
**Teste pgTAP:** `supabase/tests/20260813000007_dispute_sla_timer_test.sql`
**Invariantes:** INV-6 (`TIMESTAMPTZ`), INV-15 (replay determinístico do fato de
breach), INV-23 (`disputed_by` NUNCA limpo na retração), INV-DB (widening de
CHECK sem janela sem-constraint; `ADD COLUMN` nullable = zero-downtime).
**Risco:** Alto — costura o relógio de envelhecimento (aging) do SLA da disputa.
Falha = prazo resolvido errado (precedência contrato>org>5 quebra), janela sem
constraint no ledger durante o swap (H1), ou flag de breach duplicada/ausente.

## Objetivo

Adiciona o timer de SLA da disputa: `dispute_resolution_sla_days` em
`organizations` (NOT NULL DEFAULT 5) e `contracts` (nullable, override);
`disputed_at`/`disputed_by`/`resolution_due_at` em `sanction_review_queue`;
`_resolve_dispute_sla_days` (precedência contrato → org → 5); a varredura
`flag_sla_breached_disputes` (Q3: sinal-só, sem mudar status); e o **widening do
CHECK de tipo do ledger** para os fatos da Fase 10.6
(`DISPUTE_SLA_BREACHED`, `EVIDENCE_HASH_MISMATCH`; `DISPUTE_EVIDENCE_ATTACHED` já
presente).

## Estratégia

Estrutural + comportamental, como `postgres` (superusuário) dentro de
`BEGIN/ROLLBACK`. Funções internas com `REVOKE ALL` dos roles de API → cobertura
de cálculo roda como superusuário; os privilégios EXECUTE são provados via
`has_function_privilege`. Determinismo da varredura: linha disputada com
`resolution_due_at` no passado (`now() - INTERVAL`) → flag determinística sem
depender de relógio absoluto.

**H1 (widening sem janela):** o CHECK novo (`chk_ledger_type_v2`) é adicionado
`NOT VALID`, validado, o antigo (`chk_ledger_type`) é dropado e então o novo é
**renomeado de volta** para `chk_ledger_type` (nome canônico estável → testes e
contratos que referenciam o nome não quebram; `RENAME CONSTRAINT` é mudança só de
catálogo, sem rewrite). Teste prova: nome canônico sobrevive, nome transitório
`_v2` removido, novos tipos aceitos, lixo rejeitado (`23514`).

**M-qa / idempotência:** a varredura tem guarda `NOT EXISTS` + índice único
parcial `uq_ledger_sla_breach_once`. Teste prova: 1ª passada cria 1 fato, 2ª
passada retorna 0 (sem duplicar).

**Q3 (sinal-só):** após a flag, `status` da fila permanece `disputed` (a
varredura não muda estado, só registra o fato de breach).

## Casos pgTAP (plan = 22)

**Estrutura (5)**
1. `organizations.dispute_resolution_sla_days` existe.
2. `contracts.dispute_resolution_sla_days` existe.
3. `sanction_review_queue.disputed_at` existe.
4. `sanction_review_queue.disputed_by` existe.
5. `sanction_review_queue.resolution_due_at` existe.

**Resolução de SLA-days (3, precedência contrato → org → 5)**
6. Sem override de contrato (id não-uuid) → retorna o valor da org (7).
7. Override de contrato presente → retorna o valor do contrato (10).
8. Contrato existe mas com SLA NULL → `COALESCE` pula NULL → retorna org (7).

**Widening do CHECK do ledger (5, H1)**
9. CHECK antigo `chk_ledger_type` foi dropado.
10. CHECK novo `chk_ledger_type_v2` existe.
11. Ledger aceita `DISPUTE_SLA_BREACHED` (`lives_ok`).
12. Ledger aceita `EVIDENCE_HASH_MISMATCH` (`lives_ok`).
13. Ledger rejeita tipo inexistente → `23514`.

**Índices (2)**
14. `idx_srq_dispute_sla` existe (varredura de breach).
15. `uq_ledger_sla_breach_once` existe e é UNIQUE (idempotência M-qa).

**Varredura de breach (4)**
16. Linha disputada vencida → `flag_sla_breached_disputes()` retorna 1 e cria o
    fato `DISPUTE_SLA_BREACHED`.
17. Idempotência: 2ª passada retorna 0 (guarda `NOT EXISTS`, sem duplicar).
18. Sinal-só (Q3): após a flag, `status` da fila continua `disputed`.
19. Linha não-vencida (`resolution_due_at` no futuro) é ignorada.

**Privilégios de função (3, H4-style hardening)**
20. `authenticated` NÃO pode `EXECUTE` `flag_sla_breached_disputes` (só backend).
21. `service_role` pode `EXECUTE` `flag_sla_breached_disputes`.
22. `authenticated` NÃO pode `EXECUTE` `_resolve_dispute_sla_days` (interna).

## Notas

- `contract_id` na fila é `TEXT`; a varredura casta para `uuid`
  (`v_row.contract_id::uuid`) → fixtures usam um `contract_id` em forma de uuid.
- `_resolve_dispute_sla_days` recebe `p_contract_id TEXT` e tem guarda de
  EXCEPTION no cast (id não-uuid → trata como sem-contrato).
- Migração altera DDL exposto à Data API → `supabase/types.database.ts`
  regenerado e commitado junto.
- INV-23 (`disputed_by` nunca limpo na retração) é provado na suíte da RPC
  `resolve_dispute` (migração 008); aqui só a coluna + COMMENT são entregues.
