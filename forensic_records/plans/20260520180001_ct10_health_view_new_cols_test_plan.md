# Plano de Teste Forense — CT10 Health View New Cols Migration

**Migrations:** `20260520180001`
**Data:** 2026-05-20
**Autor:** SuperAdmin Council (Architect + Senior + QA/Security)

---

## 1. Escopo

A migration `20260520180001` recria a view `super_admin_tenant_health_view` expandindo-a com as 4 novas colunas de configuração de tenant (CT10) e mantendo a coluna `allowed_domains`:
- `clock_drift_tolerance_s`
- `data_retention_days`
- `connection_pool_limit`
- `storage_quota_gb`
- `allowed_domains`

---

## 2. Pré-condições

- [ ] Supabase local em execução (`supabase start`)
- [ ] Migration `20260520180000` já aplicada
- [ ] Tabela `organizations` com ao menos 1 organização de teste

---

## 3. Verificações de Schema (pgTAP / SQL)

### 3.1 View expõe novas colunas

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
-- Esperado: 5 linhas retornadas
```

### 3.2 View retorna dados corretos

```sql
SELECT
  clock_drift_tolerance_s,
  data_retention_days,
  connection_pool_limit,
  storage_quota_gb,
  allowed_domains
FROM public.super_admin_tenant_health_view
LIMIT 1;
-- Esperado: valores retornados com sucesso correspondendo às colunas da tabela organizations
```

---

## 4. Testes Funcionais e Integração

### 4.1 Validação do join e agregação

```sql
-- Verificar que a view executa corretamente sem erros de agrupamento/sintaxe
SELECT id, name, active_contract_count, open_critical_alert_count
FROM public.super_admin_tenant_health_view;
-- Esperado: execução com sucesso retornando dados agregados coerentes
```

---

## 5. Verificação de Segurança (INV-24 / INV-22)

```sql
-- Tentar acessar view como 'authenticated' deve falhar:
SET ROLE authenticated;
SELECT * FROM public.super_admin_tenant_health_view LIMIT 1;
-- Esperado: ERROR: permission denied for table super_admin_tenant_health_view
RESET ROLE;

-- Acesso permitido para service_role:
SET ROLE service_role;
SELECT * FROM public.super_admin_tenant_health_view LIMIT 1;
-- Esperado: Sucesso (retorna dados sem erro de permissão)
RESET ROLE;
```

---

## 6. Zero-Downtime Checklist (INV-DB)

- [ ] `DROP VIEW IF EXISTS / CREATE VIEW` — substituição de view, sem lock bloqueante e sem dependências downstream que gerem CASCADE destrutivo.

---

## 7. Rollback Strategy

Não há rollback automático (append-only). Em caso de problema:
1. Criar migration corretiva `20260520XXXXXX_fix_ct10_health_view.sql` para restaurar o estado da view.
2. Nunca modificar migrations já aplicadas (INV-3).
