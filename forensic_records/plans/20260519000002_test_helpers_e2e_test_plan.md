# Forensic Test Plan — Migration `20260519000002_test_helpers_e2e`

> **Classificação:** Engineering Study / Test Infrastructure
> **Emitido por:** QA/Security Council Persona
> **Data de emissão:** 2026-05-19
> **Migração alvo:** `supabase/migrations/20260519000002_test_helpers_e2e.sql`
> **Funções introduzidas:** `test_archive_org_for_e2e(UUID)`, `test_get_user_banned_until(UUID)`
> **Invariantes cobertos:** INV-3 (auth.users não é ledger — UPDATE seguro), INV-6 (TIMESTAMPTZ/UTC), INV-DB (DML apenas, sem DDL locks)

---

## Contexto da Investigação

O helper `_archiveOrgInDb` nos testes CT13 chamava a Admin REST API do GoTrue para banir usuários (`PUT /auth/v1/admin/users/{id}` com `ban_duration: '876000h'`). Quando qualquer linha de `auth.users` possuía `banned_until = 'infinity'` (de execuções anteriores), o GoTrue retornava HTTP 500 em **todas** as chamadas `/auth/v1/admin/users/*`, tornando o próprio setup do teste o gatilho de falhas em cascata.

A migração `20260519000001` corrigiu linhas existentes e redeclarou o RPC `super_admin_archive_organization` para usar o sentinel GoTrue-seguro `'9999-12-31 23:59:59+00'`. Esta migração introduz funções auxiliares de teste que executam as mesmas operações via SQL SECURITY DEFINER, eliminando a dependência do GoTrue no path de setup/verificação dos testes.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|------|----------------|
| PostgreSQL | ≥ 14 |
| Migração `20260519000001` aplicada | `super_admin_archive_organization` usa sentinel finito |
| Supabase local | `supabase start` + migrações aplicadas |
| Role `service_role` | Disponível para execução das RPCs de teste |

---

## Grupo 1 — `test_archive_org_for_e2e`

### Objetivo

Confirmar que a função arquiva org + bane usuários em uma única transação SQL, sem chamar GoTrue, e usando o sentinel GoTrue-seguro (INV-6).

### Casos de Teste

| # | Caso | Método | Resultado esperado |
|---|------|--------|--------------------|
| 1.1 | Org existente arquivada | `SELECT test_archive_org_for_e2e('<org_id>')` | `organizations.status = 'ARCHIVED'`, `user_roles.is_active = false`, `auth.users.banned_until = '9999-12-31 23:59:59+00'` para todos os membros |
| 1.2 | Idempotência: re-arquivar org já arquivada | Chamar função duas vezes | Não lança exceção; estado permanece o mesmo |
| 1.3 | Org inexistente | UUID inválido | Nenhuma linha afetada, função retorna sem erro |
| 1.4 | Acesso negado para `anon` | `SET ROLE anon; SELECT test_archive_org_for_e2e(...)` | `ERROR: permission denied` |
| 1.5 | Acesso permitido para `service_role` | `SET ROLE service_role; SELECT test_archive_org_for_e2e(...)` | Executa com sucesso |

---

## Grupo 2 — `test_get_user_banned_until`

### Objetivo

Confirmar que a função retorna o valor exato de `banned_until` de `auth.users` sem passar pelo GoTrue.

### Casos de Teste

| # | Caso | Método | Resultado esperado |
|---|------|--------|--------------------|
| 2.1 | Usuário com `banned_until = NULL` | `SELECT test_get_user_banned_until('<user_id>')` | `NULL` |
| 2.2 | Usuário banido com sentinel | Após `test_archive_org_for_e2e`, consultar usuário membro | `'9999-12-31 23:59:59+00'` |
| 2.3 | Usuário desbloqueado após `super_admin_unarchive_organization` | Depois de desarquivar | `NULL` |
| 2.4 | UUID inexistente | UUID de usuário que não existe | `NULL` (SELECT INTO retorna NULL para row not found) |
| 2.5 | Acesso negado para `anon` | `SET ROLE anon; SELECT test_get_user_banned_until(...)` | `ERROR: permission denied` |

---

## Grupo 3 — Integração CT13 E2E

### Objetivo

Validar que `ct13_unarchive_organization_cascade_test.dart` passa sem depender do GoTrue em nenhum ponto do setup ou verificação.

### Casos de Teste

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 3.1 | `make test-e2e-file FILE=test/integration/e2e/superadmin/ct13_unarchive_organization_cascade_test.dart` com Supabase local UP | Todos os 7 testes passam sem HTTP 500 no setup |
| 3.2 | CT13.5.3 quando CT13.5.2 falhou | Teste marcado como `skipped` (não `failed`) com mensagem explicativa |
| 3.3 | CT13.5.5 quando CT13.5.4 falhou | Teste marcado como `skipped` (não `failed`) com mensagem explicativa |

---

## Grupo 4 — Regressão `banned_until_infinity`

### Objetivo

Confirmar que o teste pgTAP (`supabase/tests/banned_until_infinity_regression_test.sql`) ainda passa após esta migração.

### Casos de Teste

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 4.1 | `make test-db` | `banned_until_infinity_regression_test.sql` — 2/2 testes ok |
| 4.2 | `test_archive_org_for_e2e` não introduz literal `'infinity'` | pgTAP Test 2 verifica pg_proc de `super_admin_archive_organization` — deve continuar passando |

---

## Segurança

- Ambas as funções têm `REVOKE EXECUTE FROM PUBLIC` + `GRANT TO service_role` — inacessíveis via PostgREST anônimo ou autenticado comum.
- Nenhuma das funções expõe dados além do escopo necessário para o helper de teste.
- Funções são `test_*` por convenção — escopo de uso restrito a ambientes de teste. Não devem ser deployadas em produção sem revisão explícita do QA/Security Council.
