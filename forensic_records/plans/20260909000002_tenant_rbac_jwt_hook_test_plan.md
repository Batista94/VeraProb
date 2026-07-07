# Plano de Testes — 20260909000002_tenant_rbac_jwt_hook

**Migração:** `supabase/migrations/20260909000002_tenant_rbac_jwt_hook.sql`  
**pgTAP:** `supabase/tests/20260909000002_tenant_rbac_jwt_hook_test.sql`  
**Invariantes:** INV-1, INV-2, INV-6

## Escopo
Estende `custom_access_token_hook` para injetar `permissions`, `perm_scopes`, `perms_v` em `app_metadata`.

## Casos
| # | Cenário | Resultado esperado |
|---|---------|-------------------|
| 1 | OPERATOR com 2 roles ativas | união distinta de 3 keys |
| 2 | TENANT_ADMIN | `permissions: ["*"]` |
| 3 | Grant `valid_until` no passado | key excluída do array |
| 4 | Grant `revoked_at` preenchido | permissões da role ignoradas |
| 5 | SuperAdmin | `["*"]` (regressão) |

## Verificação manual
```sql
SELECT public.custom_access_token_hook(
  jsonb_build_object('user_id', '<uuid>', 'claims', '{"app_metadata":{}}'::jsonb)
) -> 'claims' -> 'app_metadata';
```
