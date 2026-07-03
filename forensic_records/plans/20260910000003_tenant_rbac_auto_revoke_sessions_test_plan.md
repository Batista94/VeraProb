# Plano de Testes — 20260910000003_tenant_rbac_auto_revoke_sessions

**Migração:** `supabase/migrations/20260910000003_tenant_rbac_auto_revoke_sessions.sql`
**pgTAP:** `supabase/tests/20260910000003_tenant_rbac_auto_revoke_sessions_test.sql`
**Invariantes:** INV-1, INV-3, INV-10, INV-21, INV-22

## Escopo

`CREATE OR REPLACE revoke_tenant_role` — estende o RPC existente para, após o
soft-revoke, verificar se o role revogado contém alguma permissão `is_sensitive`.
Se sim, chama automaticamente `revoke_user_sessions(p_target_user)`, que invalida
todos os refresh tokens via Edge Function `revoke-user-sessions`.

Sem este auto-kill, um usuário com role sensível revogada poderia obter novos
access tokens (via auto-refresh do supabase_flutter) por até `jwt_expiry = 300s`
após a revogação — carregando a claim sensível no JWT durante esse intervalo.

## Casos

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| 1 | Revogar role SENSÍVEL (`sla:approve`) de um usuário | `lives_ok` + `SESSIONS_REVOKED` audit escrito |
| 2 | Revogar role NÃO-sensível (`telemetry:read`) | `lives_ok` SEM `SESSIONS_REVOKED` adicional |
| 3 | Contagem de `ROLE_REVOKED` = 2 (um por chamada) | `count = 2` |
| 4 | `SESSIONS_REVOKED` escrito exatamente 1 vez (só para o sensível) | `count = 1` |
| 5 | Ambas as rows em `user_tenant_roles` têm `revoked_at IS NOT NULL` | `count = 2` (append-only, INV-3) |

## Invariantes Verificados

- **INV-1:** org_id do caller validado por `_rbac_caller_org_id()`; revoke_user_sessions verifica org do target
- **INV-3:** rows em `user_tenant_roles` apenas marcadas com `revoked_at`, nunca deletadas
- **INV-10:** exceções `'Not found.'` e `'insufficient_privilege'` — vocabulário de domínio
- **INV-21:** `ROLE_REVOKED` + `SESSIONS_REVOKED` (quando aplicável) escritos no `system_audit_log`
- **INV-22:** cross-org bloqueado — herdado de `revoke_user_sessions` que verifica `user_roles.organization_id`

## Relação com 1.5.A (TTL)

A redução de `jwt_expiry` de 3600s → 300s (em `supabase/config.toml`) elimina a
janela de staleness para leituras via RLS. O auto-kill aqui elimina a janela para
obtenção de novos tokens sensíveis via refresh. Ambos são necessários.

## Verificação Manual

```sql
SELECT event_type, payload, occurred_at
  FROM system_audit_log
 WHERE event_type IN ('ROLE_REVOKED', 'SESSIONS_REVOKED')
 ORDER BY occurred_at DESC LIMIT 10;

SELECT user_id, tenant_role_id, revoked_at
  FROM user_tenant_roles
 WHERE user_id = '<uuid>';
```
