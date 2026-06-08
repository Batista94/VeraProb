# Plano de Testes — 20260805000002_srq_operator_name

**Migração:** `supabase/migrations/20260805000002_srq_operator_name.sql`
**Invariantes:** INV-1 (imutabilidade), INV-14 (Operator), INV-18 (Zero-Trust), INV-22, INV-24, INV-DB.
**Risco:** Médio — adiciona `operator_name` (nullable) + recria guard de imutabilidade + trigger de enqueue.

## Objetivo

Denormalizar o nome do operador na `sanction_review_queue` no momento do enqueue, resolvido da fonte autoritativa (`execution_states.bound_operator_id → drivers.full_name`, org-scoped), com fallback Zero-Trust de payload apenas quando não há binding (simulação dev).

## Casos pgTAP / SQL

1. **Coluna existe e é nullable:**
   ```sql
   SELECT is_nullable FROM information_schema.columns
   WHERE table_schema='public' AND table_name='sanction_review_queue' AND column_name='operator_name';
   -- Esperado: YES.
   ```
2. **Resolução autoritativa (INV-14):** criar execução com vehicle + driver bound; emitir ledger `SANCTION_RECOMMENDED` para o `set_id`; conferir `sanction_review_queue.vehicle_plate` e `operator_name` preenchidos com a placa e `full_name` corretos.
3. **Fallback Zero-Trust (INV-18):** emitir `SANCTION_RECOMMENDED` para um `set_id` SEM execution_state, com `payload->>'operator_name'` e `payload->>'vehicle_plate'` setados → fila recebe os valores do payload.
4. **Join autoritativo vence o payload:** com binding presente E payload divergente, a fila grava os valores do registry (join), não os do payload.
5. **Imutabilidade (INV-1):** `UPDATE sanction_review_queue SET operator_name='X' WHERE ...` → `EXCEPTION restrict_violation`.
6. **Isolamento (INV-22):** driver de outra org não resolve (`d.organization_id = NEW.organization_id`); operator_name = NULL (ou payload fallback).
7. **Idempotência (INV-24):** segundo `SANCTION_RECOMMENDED` com mesmo `ledger_entry_id` → `ON CONFLICT DO NOTHING`, 1 só linha.

## Estado esperado

`make test-db` PASS; testes de `vehicle_plate` (20260610000001) continuam verdes.
