# Plano de Testes — 20260911000001_tenant_rbac_perms_version

**Migração:** `supabase/migrations/20260911000001_tenant_rbac_perms_version.sql`
**pgTAP:** `supabase/tests/20260911000001_tenant_rbac_perms_version_test.sql`
**Invariantes:** INV-1, INV-2, INV-6, INV-22

## Escopo

Fonte autoritativa de versão de permissões para detecção de staleness no cliente
(Pilar 2 ADJ-1):

- `current_perms_v()` — `SECURITY DEFINER STABLE`, espelha o agregado exato do
  `custom_access_token_hook` (`max(tenant_roles.updated_at)` em epoch sobre as roles
  ativas, não expiradas e não revogadas do caller). Retorna `0` para portadores de
  wildcard (TENANT_ADMIN / SuperAdmin), em paridade com o hook. Cobre TODOS os tipos
  de mudança, incluindo edição de matriz de permissões que não toca `user_tenant_roles`.
- Publicação de `user_tenant_roles` em `supabase_realtime` — push escopado para
  assign/revoke; `postgres_changes` para `authenticated` é gated pelo RLS org-scoped
  da tabela (20260909000001), então Tenant-A nunca recebe eventos de Tenant-B (INV-22).

## Casos

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| 1 | `current_perms_v()` existe no schema public | `has_function` passa |
| 2 | Caller com `permissions:["*"]` (TENANT_ADMIN) | retorna `0` (short-circuit, paridade com hook) |
| 3 | Operator com 1 role ativa (`updated_at` fixado em T1) | retorna `EXTRACT(EPOCH FROM T1)` |
| 4 | Paridade com o hook para o mesmo operator | `current_perms_v()` == `perms_v` injetado pelo hook |
| 5 | Edição de matriz (bump de `updated_at` para T2) | versão muda para `EXTRACT(EPOCH FROM T2)` |
| 6 | Grant revogado (`revoked_at = NOW()`) | versão colapsa para `0` (role excluída) |
| 7 | `user_tenant_roles` publicada em `supabase_realtime` | `pg_publication_tables` contém a tabela |

## Invariantes Verificados

- **INV-1:** identidade e org do caller extraídas de `auth.jwt()->>'sub'` e
  `app_metadata.org_id`; agregação restrita ao org do caller.
- **INV-2:** função lê apenas claims do JWT para escopo; Realtime gated por RLS
  (`auth.jwt()`), nunca `auth.uid()`.
- **INV-6:** epoch derivado de `TIMESTAMPTZ`; comparações UTC.
- **INV-22:** membership de publicação apenas; RLS org-scoped garante que Tenant-A
  não recebe eventos de Tenant-B; caso 6 prova exclusão de grants inativos.

## Verificação Manual

```sql
-- Sob claims de um operator com roles ativas:
SELECT public.current_perms_v();

-- Confirmar membership de publicação:
SELECT schemaname, tablename
  FROM pg_publication_tables
 WHERE pubname = 'supabase_realtime'
   AND tablename = 'user_tenant_roles';
```
