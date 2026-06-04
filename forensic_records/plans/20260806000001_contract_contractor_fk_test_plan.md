# Plano de Testes — 20260806000001_contract_contractor_fk

**Migração:** `supabase/migrations/20260806000001_contract_contractor_fk.sql`
**Invariantes:** INV-1, INV-22, INV-DB.
**Risco:** Médio-alto — normaliza o vínculo contrato→cliente com FK + backfill de dados.

## Objetivo

Formalizar o relacionamento Contrato → Contratante (cliente da organização) com `contracts.contractor_id` (FK → `contractors`). O `contractor_name` permanece (soft-deprecate). NOT NULL no `contractor_id` fica para ciclo posterior.

## Casos pgTAP / SQL

1. **Coluna existe + nullable:** `has_column(contracts, contractor_id)` e `is_nullable = YES`.
2. **FK válida → contractors(id):** verificada via `information_schema`.
3. **Backfill promove contratante:** inserir org + contrato com `contractor_name='Cliente X'`; rodar os statements B+C da migração; conferir:
   - existe linha em `contractors` com `(organization_id, name='Cliente X')`;
   - `contracts.contractor_id` aponta para essa linha.
4. **Idempotência do backfill:** rodar B+C 2x → 1 só contractor por (org, nome), `contractor_id` estável.
5. **Isolamento (INV-22):** o join de backfill casa `organization_id` — contratante de outra org nunca é vinculado.
6. **Placeholder de enriquecimento:** contractors criados no backfill têm `primary_email` terminando em `@placeholder.invalid` (flag para enriquecimento manual posterior).

## Notas

- O backfill faz `UPDATE` em `contracts` (dispara o selo forense `seal_contracts_forensic` e o incremento de versão — comportamento esperado, re-sela a cadeia).
- Verificar cobertura: 100% dos contratos com `contractor_name` não-vazio devem receber `contractor_id` após o backfill.

## Estado esperado

`make test-db` PASS; testes existentes de contracts continuam verdes.
