# Migration Test Plan: 20260527164000_grant_standard_client_tables

## Objective
Validar a aplicação da regra INV-DATA-API-GRANT para as tabelas "Category A (Standard Client)" que existem até a data desta migração, garantindo que os papéis apropriados da Supabase API (`authenticated`, `service_role`) possuem permissões explícitas e exclusivas.

## Rationale
Tabelas criadas no esquema `public` não recebem privilégios por padrão (ou podem herdar permissões indesejadas como TRIGGER/TRUNCATE). É necessário garantir que os usuários do aplicativo (Flutter) autenticados, bem como as integrações internas que rodam com a chave `service_role`, tenham o acesso mínimo necessário às tabelas. As tabelas tratadas nesta migração são as que requerem operações de `SELECT`, `INSERT`, `UPDATE` e `DELETE` por usuários logados (via role `authenticated`).

## Execution
Os testes utilizarão o framework `pgtap` para inspecionar os privilégios granulares (grants) na base de dados, assegurando que:
- O papel `authenticated` possui APENAS os privilégios `SELECT`, `INSERT`, `UPDATE`, e `DELETE` nestas tabelas. Qualquer privilégio extra é revogado.
- O papel `service_role` possui acesso irrestrito (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`).

## Rollback / Recovery
No caso de falha nos testes, investigar se as tabelas foram criadas corretamente ou se o script de GRANT falhou. Não há risco de perda de dados. Nenhuma ação rollback complexa é necessária.

## Target Tables
1. `contracts`
2. `contractors`
3. `vehicles`
4. `routes`
5. `operational_zones`
6. `plan_declarations`
7. `contractual_service_executions`
8. `execution_states`
9. `sanction_review_queue`
10. `operational_alerts`
11. `contractual_financial_snapshot`
12. `sla_audit_ledger_v2`
13. `service_manifests`
14. `contract_rule_sets`
15. `contract_rule_versions`
16. `contractor_justifications`
17. `justification_evidence_uploads`
18. `telegram_evidence_links`
19. `telegram_evidence_metadata`
20. `telegram_user_consents`
21. `telegram_evidence_uploads`
22. `telegram_chat_bindings`
