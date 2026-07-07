# Plano de Testes — 20260910000002_tenant_rbac_revoke_sessions

**Migração:** `supabase/migrations/20260910000002_tenant_rbac_revoke_sessions.sql`
**pgTAP:** `supabase/tests/20260910000002_tenant_rbac_revoke_sessions_test.sql`
**Edge Function:** `supabase/functions/revoke-user-sessions/index.ts`
**Invariantes:** INV-1, INV-10, INV-21, INV-22, INV-26

## Escopo

RPC `revoke_user_sessions(p_target_user uuid)` — wrapper autorizado de kill de sessão
que verifica `roles:manage`, valida escopo de org, audita `SESSIONS_REVOKED` e dispara
chamada HTTP assíncrona ao Edge Function via `pg_net`.

Edge Function `revoke-user-sessions`: aceita apenas `Authorization: Bearer <SERVICE_ROLE_KEY>`,
executa `auth.admin.signOut(userId, 'global')` e grava log adicional.

## Casos

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| 1 | `revoke_user_sessions(uuid)` existe no schema public | `has_function` passa |
| 2 | Caller AUDITOR sem `roles:manage` chama RPC | throws `42501` (insufficient_privilege) |
| 3 | Caller TENANT_ADMIN (org A) tenta revogar sessão de usuário de org B | throws `42501` `'Not found.'` (INV-26 paridade) |
| 4 | Caller TENANT_ADMIN (org A) revoga sessão de usuário do mesmo org | audit row `SESSIONS_REVOKED` escrito (pg_net é fire-and-forget, testado com graceful skip se ausente) |
| 5 | Payload do audit row contém `target_user` correto | campo `payload.target_user` = UUID do target |

## Invariantes Verificados

- **INV-1:** `_rbac_caller_org_id()` valida org do caller; target verificado no mesmo org
- **INV-10:** `'insufficient_privilege'` / `'Not found.'` — mensagens de domínio, sem leakage
- **INV-21:** `SESSIONS_REVOKED` inserido ANTES da chamada HTTP (falha de rede não perde audit)
- **INV-22:** cross-org target tratado como não encontrado, indistinguível de target inexistente
- **INV-26:** erro para target de outro org = mesmo ERRCODE de target inexistente (anti-oracle)

## Configuração de Runtime (não comitada)

As seguintes configurações devem ser definidas uma vez por ambiente no Supabase Dashboard
(Database → Configuration → Settings):

```sql
ALTER DATABASE postgres SET "app.supabase_url" = 'https://<ref>.supabase.co';
ALTER DATABASE postgres SET "app.supabase_service_role_key" = '<service_role_key>';
```

## Verificação Manual

```sql
SELECT event_type, payload, occurred_at
  FROM system_audit_log
 WHERE event_type = 'SESSIONS_REVOKED'
 ORDER BY occurred_at DESC LIMIT 5;
```

```bash
# Testar Edge Function diretamente com service_role key:
curl -X POST https://<ref>.supabase.co/functions/v1/revoke-user-sessions \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"<uuid>"}'
```
