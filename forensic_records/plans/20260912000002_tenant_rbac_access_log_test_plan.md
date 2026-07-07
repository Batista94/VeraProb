# Plano de Testes — 20260912000002_tenant_rbac_access_log

**Migração:** `supabase/migrations/20260912000002_tenant_rbac_access_log.sql`
**pgTAP:** `supabase/tests/20260912000002_tenant_rbac_access_log_test.sql`
**Invariantes:** INV-1, INV-2, INV-10, INV-21, INV-26

## Escopo

`log_access_denied(route, required_perm)` — sink leve fire-and-forget do route
guard do GoRouter (Pilar 3.2). Quando um usuário do tenant acessa rota sem a
permissão, o router ejeta em silêncio para o admin hub (INV-26) e chama esta
RPC para gravar trilha imutável `ACCESS_DENIED` (INV-21). Router é
UX/defense-in-depth; RLS/RPCs continuam sendo a verdade.

- **SECURITY DEFINER** porque o `organization_id` é derivado server-side do JWT
  (`app_metadata.org_id`, convenção de claim das RPCs) via `_rbac_caller_org_id`
  (revogada dos papéis cliente). O `actor_id` é lido do claim `sub` verificado,
  então route/perm que o cliente passa não podem ser atribuídos a outro usuário.
- Chamador **não autenticado** (sem `sub`) é **no-op** — nada a atribuir.

## Casos

| # | Cenário | Resultado Esperado |
|---|---------|-------------------|
| 1 | `has_function_privilege('authenticated', …, 'EXECUTE')` | `ok` (true) |
| 2 | `has_function_privilege('service_role', …, 'EXECUTE')` | `ok` (true) |
| 3 | `has_function_privilege('anon', …, 'EXECUTE')` | `ok` (false) — sink só de cliente autenticado |
| 4 | Operator sem `financial:read` chama a RPC | `lives_ok` (grava trilha) |
| 5 | Linhas `ACCESS_DENIED` `warning` no org do chamador | `1` |
| 6 | `payload ->> 'required'` | `'financial:read'` |
| 7 | `payload ->> 'actor_id'` | = `sub` do JWT (selado, não fornecido pelo cliente) |

## Invariantes Verificados

- **INV-1/INV-2:** `organization_id` da linha derivado do JWT do chamador; sem
  parâmetro de org — impossível gravar em org alheia.
- **INV-10:** falha silenciosa controlada (no-op sem `sub`), sem exceção genérica.
- **INV-21:** trilha `ACCESS_DENIED` append-only em `system_audit_log`.
- **INV-26:** o guard que dispara esta RPC ejeta sem revelar existência da rota;
  a RPC apenas registra, não expõe nada ao chamador.

## Setup do Fixture

- Org `00000000-0000-0000-0000-0000000009f2`.
- Chamador `…09f9` — OPERATOR com `['telemetry:read']` (sem `financial:read`),
  claims apenas (sem `auth.users`; a RPC não referencia FK de usuário).
- `SELECT` de verificação após `RESET ROLE` (superuser) para não ser filtrado
  pela RLS de leitura de `system_audit_log`.

## Verificação Manual

```sql
SELECT event_type, severity, organization_id, payload
  FROM public.system_audit_log
 WHERE event_type = 'ACCESS_DENIED'
 ORDER BY occurred_at DESC LIMIT 5;
```
