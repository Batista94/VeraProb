# Migration Test Plan: 20260717000005_grant_internal_server_tables

## Objective
Validar a aplicação da regra INV-DATA-API-GRANT para as tabelas "Category C (Internal / Server-Only Tables)" que existem até a data desta migração, garantindo que elas não sejam expostas na API pública do Supabase.

## Rationale
Tabelas da Categoria C armazenam dados sensíveis de governança, auditoria, configurações internas e segurança. Nenhuma chamada cliente direta deve ser permitida a estas tabelas por motivos de segurança e para evitar vazamento de dados de outros tenants (isolamento multitenant). Portanto, as roles de cliente (`anon` e `authenticated`) devem ter absolutamente todas as permissões revogadas. A role `service_role` mantém privilégios completos (`ALL`) para possibilitar as manipulações via triggers, RPCs do tipo SECURITY DEFINER ou scripts administrativos.

## Execution
Os testes utilizarão o framework `pgtap` para inspecionar os privilégios granulares (grants) na base de dados, assegurando que:
- O papel `anon` possui zero privilégios nestas tabelas (um array de privilégios vazio).
- O papel `authenticated` possui zero privilégios nestas tabelas (um array de privilégios vazio).
- O papel `service_role` possui acesso irrestrito (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`).

## Rollback / Recovery
Em caso de falha nos testes, investigar se as tabelas foram criadas corretamente ou se o script de GRANT/REVOKE falhou. Não há risco de perda de dados. Nenhuma ação rollback complexa é necessária.

## Target Tables
1. `org_api_secrets`
2. `super_admin_users`
3. `super_admin_mfa_lockouts`
4. `super_admin_recovery_codes`
5. `super_admin_access_log`
6. `impersonation_sessions`
7. `tenant_billing_events`
8. `system_audit_log`
9. `forensic_throttle_state`
10. `forensic_throttle_events`
11. `idempotency_keys`
12. `justification_recomputation_signals`
13. `evidence_deletion_queue`
14. `justification_audit_logs`
15. `sanction_escalation_log`
16. `spoofing_audit_entries`
17. `trips_audit`
18. `shadow_executions`
19. `shadow_execution_transitions`
20. `shadow_verdicts`
21. `telegram_evidence_categories`
