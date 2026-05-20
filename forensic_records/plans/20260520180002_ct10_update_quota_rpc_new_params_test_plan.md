# Plano de Teste Forense — CT10 Update Quota RPC New Params Migration

**Migrations:** `20260520180002`
**Data:** 2026-05-20
**Autor:** SuperAdmin Council (Architect + Senior + QA/Security)

---

## 1. Escopo

A migration `20260520180002` estende a assinatura e comportamento da RPC `super_admin_update_organization_quota` para aceitar novos parâmetros de configuração de tenant (CT10):
- `p_clock_drift_tolerance_s`
- `p_data_retention_days`
- `p_connection_pool_limit`
- `p_storage_quota_gb`

---

## 2. Pré-condições

- [ ] Supabase local em execução (`supabase start`)
- [ ] Migrations `20260520180000` e `20260520180001` já aplicadas
- [ ] Tabela `organizations` com ao menos 1 organização de teste

---

## 3. Verificações de Schema (pgTAP / SQL)

### 3.1 RPC aceita novos parâmetros

```sql
SELECT proargnames
FROM pg_proc
WHERE proname = 'super_admin_update_organization_quota'
  AND pronamespace = 'public'::regnamespace;
-- Esperado: array inclui p_clock_drift_tolerance_s,
--           p_data_retention_days, p_connection_pool_limit, p_storage_quota_gb
```

---

## 4. Testes Funcionais

### 4.1 UPDATE via RPC com novos campos

```sql
-- Como usuário superadmin autenticado ou via bypass (e.g., service_role/super_admin JWT claim)
-- Simulação de chamada:
SELECT public.super_admin_update_organization_quota(
  '<ORG_UUID>',
  'professional',
  50,
  10,
  '<SUPERADMIN_UUID>',
  'Teste CT10 migration rpc new params',
  NULL,           -- capabilities
  500000,         -- tool_cost_cents
  NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
  350,   -- clock_drift_tolerance_s
  1800,  -- data_retention_days
  100,   -- connection_pool_limit
  250    -- storage_quota_gb
);

-- Verificar:
SELECT clock_drift_tolerance_s, data_retention_days,
       connection_pool_limit, storage_quota_gb
FROM public.organizations
WHERE id = '<ORG_UUID>';
-- Esperado: 350, 1800, 100, 250
```

### 4.2 Restrições e validações do input

```sql
-- Deve lançar exceção para clock_drift negativo:
SELECT public.super_admin_update_organization_quota(
  '<ORG_UUID>', 'professional', 50, 10, '<SUPERADMIN_UUID>', 'test negative drift',
  NULL, 500000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
  -1, 1800, 100, 250
);
-- Esperado: ERROR — clock_drift_tolerance_s must be >= 0

-- Deve lançar exceção para connection_pool > 500:
SELECT public.super_admin_update_organization_quota(
  '<ORG_UUID>', 'professional', 50, 10, '<SUPERADMIN_UUID>', 'test large pool',
  NULL, 500000, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
  300, 1800, 501, 250
);
-- Esperado: ERROR — connection_pool_limit must be between 1 and 500
```

### 4.3 Preservação de valores quando NULL fornecido (COALESCE)

```sql
-- Salvar valores atuais
-- Chamar RPC passando NULL para p_clock_drift_tolerance_s, p_data_retention_days, etc.
-- Verificar que os valores originais não foram alterados na tabela organizations
```

### 4.4 Audit log inclui novos campos no diff

```sql
SELECT payload -> 'before' -> 'clock_drift_tolerance_s',
       payload -> 'after'  -> 'clock_drift_tolerance_s'
FROM public.system_audit_log
WHERE organization_id = '<ORG_UUID>'
ORDER BY created_at DESC
LIMIT 1;
-- Esperado: valores before e after corretos no payload
```

---

## 5. Verificação de Segurança (INV-1 / INV-22 / INV-24)

```sql
-- Somente superadmins ou chamadas autorizadas via JWT com claim super_admin podem executar
SET ROLE authenticated;
-- Sem claim superadmin
SELECT public.super_admin_update_organization_quota(
  '<ORG_UUID>', 'professional', 50, 10, '<SUPERADMIN_UUID>', 'unauthorized test',
  NULL, 500000
);
-- Esperado: ERROR: Unauthorized: super_admin claim required
RESET ROLE;
```

---

## 6. Zero-Downtime Checklist (INV-DB)

- [ ] `CREATE OR REPLACE FUNCTION` — alteração segura da assinatura de função. Novos argumentos possuem `DEFAULT NULL`, permitindo compatibilidade e chamadas sem passar novos argumentos.

---

## 7. Rollback Strategy

Não há rollback automático (append-only). Em caso de problema:
1. Criar migration corretiva `20260520XXXXXX_fix_ct10_update_quota_rpc.sql` para restaurar assinatura ou comportamento.
2. Nunca modificar migrations já aplicadas (INV-3).
