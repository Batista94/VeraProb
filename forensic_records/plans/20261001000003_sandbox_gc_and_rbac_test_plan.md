# Plano de Teste — SLA Sandbox GC + RBAC (Phase 10.8)

- **Migração:** `supabase/migrations/20261001000003_sandbox_gc_and_rbac.sql`
- **pgTAP:** `supabase/tests/20261001000003_sandbox_gc_and_rbac_test.sql`
- **Invariantes:** INV-1, INV-3, INV-6, INV-22

## Escopo

`gc_sandbox_simulations()` + `sandbox:simulate` permission.

## Casos

| # | Caso | Resultado esperado |
|---|------|---------------------|
| 1 | Função GC existe | `has_function` ok |
| 2-3 | GC deleta sessões expiradas e seus resultados | rows deleted, count = 0 |
| 4 | GC NÃO deleta sessões não expiradas | session persiste |
| 5 | GC log em system_audit_log | evento SANDBOX_GC_EXECUTED presente |
| 6 | GC retorna 0 quando nada expirado | return = 0, nenhum log |
| 7 | Permission `sandbox:simulate` existe em tenant_permissions | ok |
| 8 | Permission auto-granted a roles com `roles:manage` | ok |

## Verificação Manual

```bash
supabase db reset && make test-db
```
