# Plano de Testes — 20260912000001_tenant_rbac_hardening

**Migração:** `supabase/migrations/20260912000001_tenant_rbac_hardening.sql`
**pgTAP:** `supabase/tests/20260912000001_tenant_rbac_hardening_test.sql`
**Invariantes:** INV-1, INV-2, INV-3, INV-10, INV-21, INV-22, INV-26

## Escopo

Correções pós-auditoria Tier-1 do Pilar 1 (F1-F4):

- **F1** — `service_role` recebe `EXECUTE` nos 6 RPCs de mutação + `revoke_user_sessions`
  (re-grant após `REVOKE … FROM PUBLIC`).
- **F2** — `approve_role_change` re-verifica o subset guard contra o **aprovador** nos
  três tipos de request (CREATE/UPDATE/GRANT), impedindo aplicação acima do teto próprio.
- **F3** — `reject_role_change` expira request >72h (`EXPIRED` + raise) em vez de gravar
  `REJECTED` enganoso.
- **F4** — `_rbac_assert_roles_manage` converge os caminhos de sucesso por
  `_rbac_live_check_permission('roles:manage')`, cobrindo os 6 RPCs num ponto só.

## Casos

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| 1-7 | `has_function_privilege('service_role', …, 'EXECUTE')` nas 7 funções (F1) | `ok` (true) |
| 8 | Claim `roles:manage` sem linha ativa em `user_tenant_roles` → `create_tenant_role` (F4) | throws `42501` `'Permission revoked or insufficient'` |
| 9 | Claim `'*'` sem linha de grant → `create_tenant_role` (F4) | `lives_ok` (bypass) |
| 10 | Aprovador só com `roles:manage` (linha viva) aprova UPDATE com `financial:export` (F2) | throws `P0001` `'PrivilegeEscalation: cannot grant unheld permission'` |
| 11 | Aprovador `'*'` aprova o mesmo UPDATE (F2) | `lives_ok` |
| 12 | Status do request após aprovação `'*'` | `'APPROVED'` |
| 13 | Aprovador só `roles:manage` aprova GRANT_ROLE de role com `financial:export` (F2) | throws `P0001` `'PrivilegeEscalation: cannot grant unheld permission'` |
| 14 | Reject de request com `created_at` -73h (F3) | throws `P0001` `'Request has expired'` |
| 15 | Reject de request fresco (F3) | `lives_ok` |
| 16 | Status do request fresco após reject | `'REJECTED'` |

## Invariantes Verificados

- **INV-1/INV-2:** claims carregam `organization_id` top-level E `app_metadata.org_id`;
  live-check valida org do caller sem tocar RLS.
- **INV-3:** `role_change_requests` só transiciona status (nunca reescreve payload).
- **INV-10:** exceções tipadas — `42501` (autorização) e `P0001`/`IntegrityException`
  (escalada/expiry), nunca genérico.
- **INV-21:** trilha `ROLE_CHANGE_APPROVED`/`ROLE_CHANGE_REJECTED` preservada nos RPCs.
- **INV-22/INV-26:** todos os requests e roles no mesmo org isolado; org derivado do JWT.

## Setup do Fixture

- Org `00000000-0000-0000-0000-0000000009f1`
- `tenant_roles`: `…09d1` (Manage Only, perm `roles:manage`), `…09d2` (Financial Export,
  perm `financial:export`), `…09d3` (Update Target).
- `user_tenant_roles`: aprovador `…09aa` ↔ role `…09d1` (linha viva → passa F4).
- Requesters/approvers (claims apenas, sem `auth.users`):
  - `…09a9` — TENANT_ADMIN `'*'`, `requested_by` de todos os requests.
  - `…09aa` — OPERATOR `['roles:manage']` com grant vivo (aprovador limitado).
  - `…09ab` — TENANT_ADMIN `'*'` (segundo aprovador soberano).
  - `…09ac` — OPERATOR `['roles:manage']` sem grant vivo (token stale, F4).
- `role_change_requests` PENDING inseridos direto (estado de entrada do RPC sob teste):
  `…09e0` (UPDATE financial:export), `…09e3` (GRANT role financeira), `…09e1`
  (UPDATE -73h), `…09e2` (UPDATE fresco).

> **Nota (rollback pgTAP):** o bloco `EXPIRED` do reject expirado (caso 14) é revertido
> pela subtransação do `throws_ok` — assim como no `approve_role_change` original. A
> asserção significativa de F3 é o raise `'Request has expired'` (o request NÃO vira
> `REJECTED`); a persistência de `EXPIRED` é cosmética e não é afirmada.

## Verificação Manual

```sql
SELECT proname, has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_exec
  FROM pg_proc p
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN ('create_tenant_role','update_tenant_role_permissions',
                   'assign_tenant_role','revoke_tenant_role','approve_role_change',
                   'reject_role_change','revoke_user_sessions');

SELECT status, decided_by FROM role_change_requests ORDER BY created_at DESC LIMIT 5;
```
