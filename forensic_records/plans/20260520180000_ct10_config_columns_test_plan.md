# Plano de Teste Forense — CT10 Config Columns Migration

**Migrations:** `20260520180000`, `20260520180001`, `20260520180002`
**Data:** 2026-05-20
**Autor:** SuperAdmin Council (Architect + Senior + QA/Security)

---

## 1. Escopo

As três migrations adicionam suporte aos campos avançados de configuração de tenant (CT10):
- `clock_drift_tolerance_s` — Motor Forense
- `data_retention_days` — Compliance
- `connection_pool_limit` — Infraestrutura
- `storage_quota_gb` — Infraestrutura

---

## 2. Pré-condições

- [ ] Supabase local em execução (`supabase start`)
- [ ] Migrations anteriores aplicadas até `20260706000010`
- [ ] Tabela `organizations` com ao menos 1 organização de teste

---

## 3. Verificações de Schema (pgTAP / SQL)

### 3.1 Colunas novas existem

```sql
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'organizations'
  AND column_name IN (
    'clock_drift_tolerance_s',
    'data_retention_days',
    'connection_pool_limit',
    'storage_quota_gb'
  );
-- Esperado: 4 linhas, todas NOT NULL, com defaults corretos
```

### 3.2 Defaults corretos

```sql
SELECT
  clock_drift_tolerance_s,
  data_retention_days,
  connection_pool_limit,
  storage_quota_gb
FROM public.organizations
LIMIT 1;
-- Esperado: 300, 1825, 60, 100
```

### 3.3 Constraints existem

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.organizations'::regclass
  AND conname IN (
    'chk_clock_drift_tolerance_s',
    'chk_data_retention_days',
    'chk_connection_pool_limit',
    'chk_storage_quota_gb'
  );
-- Esperado: 4 linhas
```

### 3.4 View expõe novas colunas

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'super_admin_tenant_health_view'
  AND column_name IN (
    'clock_drift_tolerance_s',
    'data_retention_days',
    'connection_pool_limit',
    'storage_quota_gb',
    'allowed_domains'
  );
-- Esperado: 5 linhas
```

### 3.5 RPC aceita novos parâmetros

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
-- Como usuário superadmin autenticado:
SELECT public.super_admin_update_organization_quota(
  '<ORG_UUID>',
  'professional',
  50,
  10,
  '<SUPERADMIN_UUID>',
  'Teste CT10 migration',
  NULL,           -- capabilities
  500000,         -- tool_cost_cents
  NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
  300,   -- clock_drift_tolerance_s
  1825,  -- data_retention_days
  50,    -- connection_pool_limit
  500    -- storage_quota_gb
);

-- Verificar:
SELECT clock_drift_tolerance_s, data_retention_days,
       connection_pool_limit, storage_quota_gb
FROM public.organizations
WHERE id = '<ORG_UUID>';
-- Esperado: 300, 1825, 50, 500
```

### 4.2 Constraint violation: clock_drift negativo

```sql
-- Deve lançar exceção:
UPDATE public.organizations
SET clock_drift_tolerance_s = -1
WHERE id = '<ORG_UUID>';
-- Esperado: ERROR — check constraint violation
```

### 4.3 Constraint violation: connection_pool > 500

```sql
UPDATE public.organizations
SET connection_pool_limit = 501
WHERE id = '<ORG_UUID>';
-- Esperado: ERROR — check constraint violation
```

### 4.4 RPC com NULL nos 4 novos campos (COALESCE preserva)

```sql
-- Salvar valores atuais
-- Chamar RPC com p_clock_drift=NULL, etc.
-- Verificar que valores originais foram mantidos
```

### 4.5 Audit log inclui novos campos no diff

```sql
SELECT payload -> 'before' -> 'clock_drift_tolerance_s',
       payload -> 'after'  -> 'clock_drift_tolerance_s'
FROM public.system_audit_log
WHERE organization_id = '<ORG_UUID>'
ORDER BY created_at DESC
LIMIT 1;
-- Esperado: valores before e after presentes
```

---

## 5. Verificação de Segurança (INV-24)

```sql
-- Tentar acessar view como 'authenticated' deve falhar:
SET ROLE authenticated;
SELECT * FROM public.super_admin_tenant_health_view LIMIT 1;
-- Esperado: permission denied
RESET ROLE;
```

---

## 6. Zero-Downtime Checklist (INV-DB)

- [ ] `ADD COLUMN IF NOT EXISTS` com DEFAULT — operação instantânea no PG 11+
- [ ] `CHECK NOT VALID` — sem lock de leitura/escrita
- [ ] `VALIDATE CONSTRAINT` — adquire `SHARE UPDATE EXCLUSIVE` (não bloqueia DML)
- [ ] `DROP VIEW / CREATE VIEW` — não há dependentes (sem mat views)
- [ ] `CREATE OR REPLACE FUNCTION` — sem drop da signature existente

---

## 7. Rollback Strategy

Não há rollback automático (append-only). Em caso de problema:
1. Identificar a migration com erro
2. Criar migration corretiva `20260520XXXXXX_fix_ct10_...sql`
3. Nunca modificar migrations já aplicadas (INV-3)
