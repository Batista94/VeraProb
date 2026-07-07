# Plano de Testes — 20260910000001_tenant_rbac_live_check

**Migração:** `supabase/migrations/20260910000001_tenant_rbac_live_check.sql`
**pgTAP:** `supabase/tests/20260910000001_tenant_rbac_live_check_test.sql`
**Invariantes:** INV-1, INV-2, INV-10, INV-21, INV-22

## Escopo

Helper `_rbac_live_check_permission(text)` + injeção aditiva do live-check nas funções
`approve_sanction` e `reject_sanction`. Cobre também os casos de sucesso e bloqueio
de auto-aprovação do workflow four-eyes (`approve_role_change`).

## Casos

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| 1 | `_rbac_live_check_permission(text)` existe no schema public | `has_function` passa |
| 2 | `approve_role_change` aprovado por segundo admin (admin2 aprova request de admin1) | `lives_ok` — sem exceção |
| 3 | Status do request após aprovação | `'APPROVED'` |
| 4 | Audit row `ROLE_CHANGE_APPROVED` escrito em `system_audit_log` | `count = 1` |
| 5 | Auto-aprovação bloqueada (admin2 tenta aprovar próprio request) | throws P0001 `'Self-approval is not permitted'` |
| 6 | Token stale (`sla:approve` em JWT, grant revogado no DB) → `approve_sanction` | throws `42501` `'Permission revoked or insufficient'` |
| 7 | Token stale (`sla:approve` em JWT, grant revogado no DB) → `reject_sanction` | throws `42501` `'Permission revoked or insufficient'` |
| 8 | (Implícito) AUDITOR coarse-role sem custom permissions passa pelo live-check sem bloqueio | exceção propagada é `'Sanction approval rejected.'`, não live-check |

## Invariantes Verificados

- **INV-1:** org_id do caller validado pelo live-check via `app_metadata.org_id`
- **INV-2:** live-check não toca RLS — é verificação pontual dentro de RPC SECURITY DEFINER
- **INV-10:** exceção `42501` com mensagem de domínio, nunca Exception/StateError genérico
- **INV-21:** `ROLE_CHANGE_APPROVED` inserido no `system_audit_log` (append-only)
- **INV-22:** Fixture usa usuário stale isolado no mesmo org; sem cross-tenant neste test

## Setup do Fixture

- Org `00000000-0000-0000-0000-000000001001`
- admin1 (`...1011`, TENANT_ADMIN) — cria requests
- admin2 (`...1012`, TENANT_ADMIN) — aprova requests de admin1
- stale_user (`...1013`, AUDITOR + JWT `permissions:["sla:approve"]`, grant `revoked_at IS NOT NULL`)
- `tenant_role` `LC-Approver` com `sla:approve`; `user_tenant_roles` para stale_user com `revoked_at = NOW()`

## Verificação Manual

```sql
SELECT event_type, payload
  FROM system_audit_log
 WHERE event_type IN ('ROLE_CHANGE_APPROVED', 'ROLE_CHANGE_REJECTED')
 ORDER BY occurred_at DESC LIMIT 5;

SELECT status, decided_by
  FROM role_change_requests
 ORDER BY created_at DESC LIMIT 5;
```
