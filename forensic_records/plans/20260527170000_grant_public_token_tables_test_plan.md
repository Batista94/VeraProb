# Migration Test Plan: 20260527170000_grant_public_token_tables

## Objective
Validar a aplicação da regra INV-DATA-API-GRANT para as tabelas "Category B (Public / Token Tables)" que existem até a data desta migração, garantindo que os papéis apropriados da Supabase API (`anon`, `authenticated`, `service_role`) possuem permissões explícitas e exclusivas.

## Rationale
Tabelas da Categoria B são acessadas por fluxos não autenticados (anonymous) e autenticados (authenticated) via API pública do Supabase (como fluxos de tokens de revisão de contratos, vinculação do Telegram e submissão de justificativas). É crítico aplicar o privilégio mínimo de forma explícita, revogando privilégios extras indesejados (como DELETE ou TRUNCATE) das roles `anon` e `authenticated`, mas concedendo `SELECT`, `INSERT` e `UPDATE` necessários para o funcionamento destes fluxos sem exigir privilégios de superusuário. A role `service_role` mantém privilégios completos (`ALL`).

## Execution
Os testes utilizarão o framework `pgtap` para inspecionar os privilégios granulares (grants) na base de dados, assegurando que:
- O papel `anon` possui APENAS os privilégios `SELECT`, `INSERT` e `UPDATE` nestas tabelas. Qualquer outro privilégio é revogado.
- O papel `authenticated` possui APENAS os privilégios `SELECT`, `INSERT` e `UPDATE` nestas tabelas. Qualquer outro privilégio é revogado.
- O papel `service_role` possui acesso irrestrito (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`).

## Rollback / Recovery
No caso de falha nos testes, investigar se as tabelas foram criadas corretamente ou se o script de GRANT falhou. Não há risco de perda de dados. Nenhuma ação rollback complexa é necessária.

## Target Tables
1. `contract_review_tokens`
2. `telegram_binding_tokens`
3. `telegram_pending_links`
4. `justification_submission_tokens`
