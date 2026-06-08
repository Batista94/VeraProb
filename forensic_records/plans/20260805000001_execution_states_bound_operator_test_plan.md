# Plano de Testes — 20260805000001_execution_states_bound_operator

**Migração:** `supabase/migrations/20260805000001_execution_states_bound_operator.sql`
**Invariantes:** INV-1, INV-14 (Asset/Operator/Execution), INV-15, INV-22, INV-DB.
**Risco:** Médio — adiciona binding de operador (coluna nullable) e recria RPC `create_execution_for_operator`.

## Objetivo

Completar o triângulo agnóstico (Asset + Operator + Execution): `execution_states` passa a guardar `bound_operator_id` (FK → drivers), persistido pelo RPC de criação de execução. Habilita a denormalização do nome do operador na fila de auditoria (ver `20260805000002`).

## Casos pgTAP / SQL

1. **Coluna existe e é nullable:**
   ```sql
   SELECT column_name, is_nullable, data_type
   FROM information_schema.columns
   WHERE table_schema='public' AND table_name='execution_states' AND column_name='bound_operator_id';
   -- Esperado: 1 linha, is_nullable='YES', data_type='uuid'.
   ```
2. **FK válida → drivers(id):** inserir execution com `bound_operator_id` inexistente deve violar FK; com driver válido deve passar. `ON DELETE SET NULL` confirmado.
3. **RPC persiste binding (INV-14):** chamar `create_execution_for_operator(... p_driver_id, p_vehicle_id ...)` com JWT da org; conferir `SELECT bound_vehicle_id, bound_operator_id FROM execution_states WHERE set_id = <retornado>` → ambos preenchidos.
4. **Idempotência (INV-15):** chamar o RPC 2x com mesmos inputs → mesmo `set_id`, 1 só linha em execution_states (`ON CONFLICT DO NOTHING`).
5. **Fail-Fast org (INV-1):** chamar com `p_organization_id` ≠ claim do JWT → `EXCEPTION org_mismatch`.
6. **Isolamento (INV-22):** o join de resolução filtra `drivers.organization_id` — operador de outra org não resolve.

## Estado esperado

`make test-db` PASS; nenhuma quebra nos testes existentes de `create_execution_for_operator`.
