# Plano de Testes — 20260909000001_tenant_rbac_schema

**Migração:** `supabase/migrations/20260909000001_tenant_rbac_schema.sql`  
**pgTAP:** `supabase/tests/20260909000001_tenant_rbac_schema_test.sql`  
**Invariantes:** INV-1, INV-2, INV-22, INV-26, INV-DATA-API-GRANT

## Escopo
- Criação das 5 tabelas (`tenant_permissions`, `tenant_roles`, `tenant_role_permissions`, `user_tenant_roles`, `role_change_requests`)
- Seed do dicionário global de permissões (`module:action`)
- RLS org-scoped SELECT + REVOKE de DML para `authenticated`
- Grants explícitos SELECT para `authenticated`

## Casos
| # | Cenário | Resultado esperado |
|---|---------|-------------------|
| 1 | Tabelas existem | `has_table` OK |
| 2 | Seed ≥ 10 permissões | `roles:manage` sensível |
| 3 | `authenticated` INSERT em `tenant_roles` | negado (grant layer) |
| 4 | SELECT cross-tenant | 0 linhas (teste integrado) |

## Verificação manual
```sql
SELECT key, is_sensitive, is_scopable FROM tenant_permissions ORDER BY key;
SELECT has_table_privilege('authenticated','public.tenant_roles','SELECT');
SELECT has_table_privilege('authenticated','public.tenant_roles','INSERT'); -- false
```
