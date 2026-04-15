# VeraProb Invariants Reference (CLAUDE.md)

Este documento mapeia as restrições técnicas obrigatórias que devem ser verificadas durante a auditoria de qualquer skill ou instrução AI.

## INV-1: IDENTITY SOVEREIGNTY
- **Regra:** Todo dado pertence a um `organization_id`. Toda query e fluxo deve filtrar por `organization_id`.
- **Alvo de Auditoria:** Scripts SQL ou Repositories que não incluam `organization_id` ou que filtrem por `auth.uid()` em vez de `auth.jwt() ->> 'organization_id'`.

## INV-3: LEDGER INTEGRITY (APPEND-ONLY)
- **Regra:** Proibido UPDATE ou DELETE em `ledger`, `events`, `facts` ou `financial_records`.
- **Alvo de Auditoria:** Qualquer instrução que peça para "ajustar", "corrigir arquivo" ou "remover entrada" do registro financeiro.

## INV-4: MONEY TYPE
- **Regra:** Valer financeiro deve ser `BIGINT` (cents) no DB e o Value Object `Money` no Domínio. Proibido `double` para dinheiro.

## INV-6: UTC DETERMINISM
- **Regra:** Uso obrigatório de `IDateTimeProvider.nowUtc()`. Proibido `DateTime.now()` diretamente nas camadas de domínio, aplicação e infraestrutura.

## INV-13: LAYER BOUNDS
- **Regra:** Camadas de Features/Presentation nunca importam Domínio ou Infraestrutura diretamente. Devem passar pelos Handlers da Aplicação.

## INV-15: DETERMINISM
- **Regra:** A computação deve produzir resultados idênticos bit-a-bit no replay.

## INV-22: MULTI-TENANCY ISOLATION
- **Regra:** Garantir que Tenant-A nunca veja dados de Tenant-B.
