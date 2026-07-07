# Plano de Testes — 20260909000003_tenant_rbac_permission_helpers

**Migração:** `supabase/migrations/20260909000003_tenant_rbac_permission_helpers.sql`  
**pgTAP:** `supabase/tests/20260909000003_tenant_rbac_permission_helpers_test.sql`  
**Invariantes:** INV-2, INV-7

## Escopo
Funções STABLE `public.has_permission(text)` e `public.has_permission_on(text, uuid)` — O(1), sem JOIN. (Supabase bloqueia DDL no schema `auth`; semântica idêntica ao desenho `auth.has_permission`.)

## Casos
| # | Cenário | Resultado |
|---|---------|-----------|
| 1 | Key presente no JWT | `true` |
| 2 | Key ausente | `false` |
| 3 | Wildcard `*` | `true` para qualquer key |
| 4 | Sem entrada em `perm_scopes` | `has_permission_on` irrestrito |
| 5 | Recurso fora do allowlist | `false` |

## Verificação manual
```sql
SET LOCAL request.jwt.claims = '{"app_metadata":{"permissions":["financial:read"],"perm_scopes":{}}}';
SELECT public.has_permission('financial:read');
```
