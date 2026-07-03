# Plano de Testes — 20260909000004_tenant_rbac_mutation_rpcs

**Migração:** `supabase/migrations/20260909000004_tenant_rbac_mutation_rpcs.sql`  
**pgTAP:** `supabase/tests/20260909000004_tenant_rbac_mutation_rpcs_test.sql`  
**Invariantes:** INV-1, INV-10, INV-21, INV-22, INV-26

## Escopo
RPCs SECURITY DEFINER: `create_tenant_role`, `update_tenant_role_permissions`, `assign_tenant_role`, `revoke_tenant_role`, `approve_role_change`, `reject_role_change`.

## Casos
| # | Cenário | Resultado |
|---|---------|-----------|
| 1 | Subset guard — grant não possuído | `PrivilegeEscalation` P0001 |
| 2 | Key inválida no dicionário | IntegrityException P0001 |
| 3 | `assign` role de outra org | 42501 Not found |
| 4 | Permissão sensível em create | `role_change_requests` PENDING |
| 5 | Self-approve | bloqueado (CHECK + RPC) |
| 6 | `is_system` role update | IntegrityException |

## Verificação manual
```sql
SELECT public.create_tenant_role('Test', NULL, '[{"key":"telemetry:read"}]'::jsonb);
SELECT event_type FROM system_audit_log WHERE source = 'tenant_rbac_rpc' ORDER BY occurred_at DESC LIMIT 5;
```
