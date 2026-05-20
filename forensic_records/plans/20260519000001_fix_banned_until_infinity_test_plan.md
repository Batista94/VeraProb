# Forensic Test Plan — Migration `20260519000001_fix_banned_until_infinity`

> **Classificação:** Engineering Study / Bug Fix / Regression Guard
> **Emitido por:** QA/Security Council Persona
> **Data de emissão:** 2026-05-19
> **Migração alvo:** `supabase/migrations/20260519000001_fix_banned_until_infinity.sql`
> **Operações:** `UPDATE auth.users` (Step 1) + `CREATE OR REPLACE FUNCTION super_admin_archive_organization` (Step 2)
> **Invariantes cobertos:** INV-3 (auth.users não é ledger — UPDATE seguro), INV-6 (TIMESTAMPTZ/UTC), INV-26 (404-parity), INV-DB (DML apenas, sem DDL locks)

---

## Contexto da Investigação

PostgreSQL aceita `'infinity'` como literal `TIMESTAMPTZ` válido, mas o GoTrue (servidor auth Go do Supabase) usa `time.Time` internamente, que não consegue deserializar o literal `'infinity'`. Qualquer linha em `auth.users` com `banned_until = 'infinity'` faz o GoTrue retornar HTTP 500 com `{"message":"Database error finding users"}` em **todas** as chamadas `/auth/v1/admin/users/*`.

Efeito cascata observado:
- `_ensureUser` recebe HTTP 422 (usuário já existe), chama `GET /auth/v1/admin/users?email=...` para obter o `user_id`.
- GoTrue retorna HTTP 500 (corpo `{"message":"..."}`, sem chave `users`).
- Cast `response['users'] as List<dynamic>` lança `type 'Null' is not a subtype of type 'List<dynamic>'`.
- Testes `rls_isolation_test.dart` e `jwt_hook_e2e_test.dart` falham no **setup**, não no assert — dificultando diagnóstico.

**Correção:** duas etapas atômicas na migração:
1. `UPDATE auth.users SET banned_until = '9999-12-31 23:59:59+00' WHERE banned_until = 'infinity'` — repara linhas existentes.
2. `CREATE OR REPLACE FUNCTION super_admin_archive_organization` — redeclara o RPC substituindo o literal `'infinity'` pelo sentinel GoTrue-seguro `'9999-12-31 23:59:59+00'::timestamptz`.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|------|----------------|
| PostgreSQL | ≥ 14 |
| Supabase local | `supabase start` + migrações até `20260519000000` aplicadas |
| Tabela `organizations` | Presente com coluna `status` (`'ACTIVE'`, `'ARCHIVED'`, `'DELETED'`) |
| Tabela `user_roles` | Presente com coluna `organization_id` e `is_active` |
| Tabela `auth.users` | Presente (schema Supabase padrão) |
| Role `service_role` | Disponível para execução das RPCs de teste |
| Role `super_admin` | JWT com `app_metadata.super_admin = 'true'` para testes de JWT guard |

---

## Grupo 1 — Reparo de Dados Existentes (Step 1 da Migração)

### Objetivo

Confirmar que o `UPDATE` do Step 1 corrige todas as linhas com `banned_until = 'infinity'` sem afetar linhas `NULL` ou linhas já usando o sentinel correto.

### Casos de Teste

| # | Caso | Setup | Resultado esperado |
|---|------|-------|--------------------|
| 1.1 | Happy path: linhas com `infinity` convertidas | Inserir row com `banned_until = 'infinity'` antes da migração | Após migração: `banned_until = '9999-12-31 23:59:59+00'` |
| 1.2 | Linhas `NULL` não afetadas | Row com `banned_until = NULL` | Permanece `NULL` após migração |
| 1.3 | Linhas com sentinel correto não afetadas | Row com `banned_until = '9999-12-31 23:59:59+00'` | Permanece `'9999-12-31 23:59:59+00'` (UPDATE não duplica) |
| 1.4 | Linhas com ban temporário válido não afetadas | Row com `banned_until = '2030-01-01 00:00:00+00'` | Permanece inalterada |
| 1.5 | Zero linhas infinity pós-migração | Executar `SELECT COUNT(*) FROM auth.users WHERE banned_until = 'infinity'::timestamptz` | Retorna `0` |

**Script de verificação (CT-1.5 — CI Gate via pgTAP):**

```sql
SELECT is(
  (SELECT COUNT(*)::int FROM auth.users WHERE banned_until = 'infinity'::timestamptz),
  0,
  'GoTrue guard: no auth.users rows have banned_until = infinity'
);
```

> Este teste é executado automaticamente via `supabase/tests/banned_until_infinity_regression_test.sql` (Test 1). Execute com `make test-db`.

---

## Grupo 2 — RPC `super_admin_archive_organization` Redeclarado (Step 2)

### Objetivo

Confirmar que o RPC redeclarado usa o sentinel GoTrue-seguro e que os guards de segurança (JWT, 404-parity, idempotência) estão íntegros.

### CT-2.1: Corpo do RPC não contém literal `'infinity'` (CI Gate via pgTAP)

**Hipótese forense:** O `CREATE OR REPLACE FUNCTION` substitui o corpo do RPC na memória do PostgreSQL (`pg_proc.prosrc`). Qualquer referência ao literal `'infinity'` em atribuições `banned_until = 'infinity'` deve ser ausente.

```sql
-- RESULTADO ESPERADO: ok (NOT EXISTS retorna true)
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM   pg_proc p
    JOIN   pg_namespace n ON p.pronamespace = n.oid
    WHERE  n.nspname = 'public'
      AND  p.proname = 'super_admin_archive_organization'
      AND  p.prosrc ~ 'banned_until\s*=\s*''infinity'''
  ),
  'super_admin_archive_organization: banned_until assignment does not use infinity literal'
);
```

> Este teste é executado automaticamente via `supabase/tests/banned_until_infinity_regression_test.sql` (Test 2). Execute com `make test-db`.

**Critério de falha:** `pg_proc.prosrc` ainda contém `banned_until = 'infinity'` — indica que o `CREATE OR REPLACE` não foi aplicado ou foi revertido por uma migração posterior.

---

### CT-2.2: Happy path — Arquivar org com usuários ativos

**Setup:**
```sql
-- Criar org ativa de teste
INSERT INTO organizations (id, name, status) VALUES
  ('11111111-0000-0000-0000-000000000001', 'Org Teste Archive', 'ACTIVE');

-- Criar usuário e role
INSERT INTO auth.users (id, email) VALUES
  ('22222222-0000-0000-0000-000000000001', 'usuario@teste.com');

INSERT INTO user_roles (user_id, organization_id, is_active) VALUES
  ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', true);
```

**Execução:**
```sql
SELECT super_admin_archive_organization(
  '11111111-0000-0000-0000-000000000001',
  'Teste CT-2.2',
  '33333333-0000-0000-0000-000000000001'  -- super_admin_id fictício
);
```

**Verificações:**
```sql
-- Org arquivada
SELECT status FROM organizations WHERE id = '11111111-0000-0000-0000-000000000001';
-- Esperado: 'ARCHIVED'

-- user_role desativado
SELECT is_active FROM user_roles WHERE organization_id = '11111111-0000-0000-0000-000000000001';
-- Esperado: false

-- banned_until usa sentinel finito (não 'infinity')
SELECT banned_until FROM auth.users WHERE id = '22222222-0000-0000-0000-000000000001';
-- Esperado: '9999-12-31 23:59:59+00' (NÃO 'infinity')
```

**Critério de aceitação:** `status = 'ARCHIVED'`, `is_active = false`, `banned_until = '9999-12-31 23:59:59+00'`.

---

### CT-2.3: JWT guard — `super_admin` claim ausente

**Hipótese forense:** Chamadas sem `app_metadata.super_admin = 'true'` devem ser rejeitadas com `insufficient_privilege` (ERRCODE `42501`).

```sql
-- Simular JWT sem claim super_admin (authenticated comum)
SET LOCAL request.jwt.claims = '{"sub": "user-uuid", "app_metadata": {}}';

SELECT super_admin_archive_organization(
  '11111111-0000-0000-0000-000000000001',
  'Tentativa não autorizada',
  'user-uuid'
);
-- ESPERADO: ERROR 42501: Unauthorized: super_admin claim required
```

**Critério de aceitação:** Lança `insufficient_privilege`. Nenhuma linha alterada em `organizations`, `user_roles`, `auth.users`, `system_audit_log`.

---

### CT-2.4: 404-parity — Org inexistente (INV-26)

**Hipótese forense:** UUID inválido ou de org com `status = 'DELETED'` deve retornar `P0002` (Not Found), impedindo oracle de enumeração de organizações.

```sql
SELECT super_admin_archive_organization(
  'ffffffff-ffff-ffff-ffff-ffffffffffff',  -- UUID inexistente
  'Tentativa 404',
  '33333333-0000-0000-0000-000000000001'
);
-- ESPERADO: ERROR P0002: Not found
```

**Critério de aceitação:** Lança `P0002`. Comportamento idêntico para UUID de org `DELETED` (anti-oracle: não revela se a org já existiu).

---

### CT-2.5: Idempotência — Org já arquivada

**Hipótese forense:** Chamar o RPC em org com `status = 'ARCHIVED'` deve lançar `P0003` (já arquivada), não re-executar as operações de cascata.

```sql
-- Org já arquivada pelo CT-2.2
SELECT super_admin_archive_organization(
  '11111111-0000-0000-0000-000000000001',
  'Segunda tentativa',
  '33333333-0000-0000-0000-000000000001'
);
-- ESPERADO: ERROR P0003: Organization already archived
```

**Critério de aceitação:** Lança `P0003`. Sem entradas duplicadas em `system_audit_log`. Contagem de `user_roles` inalterada.

---

### CT-2.6: Cascade completo — API secrets, invitations, impersonation sessions

**Setup:** Criar fixtures com `org_api_secrets.revoked_at = NULL`, `invitations.revoked_at_utc = NULL`, `impersonation_sessions.revoked_at = NULL` para a org-alvo.

**Verificações pós-archive:**
```sql
-- Secrets revogados
SELECT COUNT(*) FROM org_api_secrets
WHERE organization_id = '<org_id>' AND revoked_at IS NULL;
-- Esperado: 0

-- Invitations revogadas
SELECT COUNT(*) FROM invitations
WHERE organization_id = '<org_id>'
  AND accepted_at_utc IS NULL AND revoked_at_utc IS NULL;
-- Esperado: 0

-- Impersonation sessions revogadas
SELECT COUNT(*) FROM impersonation_sessions
WHERE target_org_id = '<org_id>' AND revoked_at IS NULL;
-- Esperado: 0
```

**Critério de aceitação:** Todas as cascatas executam em uma única transação. Rollback automático se qualquer step falhar.

---

### CT-2.7: Audit log gerado

```sql
SELECT event_type, severity, organization_id
FROM system_audit_log
WHERE organization_id = '11111111-0000-0000-0000-000000000001'
  AND event_type = 'ORG_ARCHIVED'
ORDER BY created_at DESC
LIMIT 1;
```

**Critério de aceitação:** Linha presente com `event_type = 'ORG_ARCHIVED'`, `severity = 'warning'`, `organization_id` correto.

---

## Grupo 3 — Regressão GoTrue (Integração)

### Objetivo

Confirmar que após a migração, o GoTrue não retorna HTTP 500 nas chamadas de listing de usuários — pré-condição para os helpers de E2E (`_ensureUser`) funcionarem corretamente.

### Casos de Teste

| # | Caso | Resultado esperado |
|---|------|--------------------|
| 3.1 | `GET /auth/v1/admin/users?email=...` após migração | HTTP 200 com body `{"users": [...]}` — não HTTP 500 |
| 3.2 | `_ensureUser` com usuário existente | Helper obtém `user_id` sem `type 'Null' is not a subtype of type 'List<dynamic>'` |
| 3.3 | `make test-db` passa após migração | `banned_until_infinity_regression_test.sql` — 2/2 tests ok |
| 3.4 | `make test-e2e-file FILE=test/integration/e2e/superadmin/ct13_unarchive_organization_cascade_test.dart` | Todos os 7 subtestes passam sem HTTP 500 no setup |

---

## Grupo 4 — Zero-Downtime (INV-DB)

### Objetivo

Confirmar que a migração não adquire locks bloqueantes de longa duração.

### CT-4.1: Justificativa forense de zero-downtime

| Operação | Lock adquirido | Escopo | Bloqueia INSERTs? |
|----------|----------------|--------|-------------------|
| `UPDATE auth.users WHERE banned_until = 'infinity'` | `RowExclusiveLock` em `auth.users` | Apenas linhas matching (pequeno conjunto) | Não |
| `CREATE OR REPLACE FUNCTION` | `AccessExclusiveLock` em `pg_proc` | Catálogo (~ms) | Não |

**Critério de aceitação:** Workload concorrente de INSERT em `auth.users` (usuários novos via GoTrue) não é bloqueado durante a aplicação da migração. Tempo de aplicação < 500ms em produção (conjuntos de dados típicos: < 10.000 usuários com `banned_until = 'infinity'`).

### CT-4.2: Idempotência da migração

Re-executar o Step 1 manualmente:
```sql
UPDATE auth.users
SET    banned_until = '9999-12-31 23:59:59+00'::timestamptz
WHERE  banned_until = 'infinity'::timestamptz;
-- Esperado: UPDATE 0 (nenhuma linha afetada — todas já corrigidas)
```

Re-executar o Step 2 (via `CREATE OR REPLACE`) não deve gerar erro. O corpo do RPC permanece idêntico após re-execução.

---

## Matriz de Rastreabilidade

| Caso | Invariante | Tipo | Automatizável? | Prioridade |
|------|-----------|------|----------------|------------|
| CT-1.5 | INV-6, INV-DB | pgTAP CI Gate | Sim (`make test-db`) | P0 — Bloqueante |
| CT-2.1 | INV-6 | pgTAP CI Gate | Sim (`make test-db`) | P0 — Bloqueante |
| CT-2.2 | INV-6, INV-3 | SQL Integration | Sim (psql fixture) | P0 — Bloqueante |
| CT-2.3 | INV-2 (JWT) | Security Test | Sim (psql SET LOCAL) | P0 — Bloqueante |
| CT-2.4 | INV-26 | Anti-Oracle | Sim (psql) | P0 — Bloqueante |
| CT-2.5 | INV-3 | Idempotency | Sim (psql) | P0 — Bloqueante |
| CT-2.6 | INV-1, INV-22 | Cascade Integration | Sim (psql fixture) | P0 — Bloqueante |
| CT-2.7 | INV-21 (Audit) | Schema Check | Sim (psql) | P1 |
| CT-3.1 | INV-6 (GoTrue compat) | Integration/HTTP | Manual (GoTrue local) | P0 — Bloqueante |
| CT-3.3 | INV-6 | pgTAP CI | Sim (`make test-db`) | P0 — Bloqueante |
| CT-3.4 | INV-1, INV-22 | E2E | Sim (`make test-e2e`) | P0 — Bloqueante |
| CT-4.1 | INV-DB | Observability | Manual (pg_stat_activity) | P0 — Bloqueante |
| CT-4.2 | INV-DB | Idempotency | Sim (psql) | P1 |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 — Bloqueante** devem passar antes do merge.

| Gate | Condição |
|------|----------|
| **PASS** | CT-1.5: `COUNT(*) = 0` para `banned_until = 'infinity'`; CT-2.1: `pg_proc` não contém literal `'infinity'` em `super_admin_archive_organization`; CT-2.2: cascade correto com sentinel `'9999-12-31 23:59:59+00'`; CT-2.3: `42501` para JWT sem `super_admin`; CT-2.4: `P0002` para org inexistente; CT-2.5: `P0003` para org já arquivada; CT-3.3: `make test-db` 2/2 ok; CT-3.4: E2E 7/7 subtestes ok |
| **VETO** | Qualquer P0 com resultado diferente do esperado |
| **WARN** | CT-3.1 não testado localmente (sem GoTrue up) — aceito se CT-3.3 e CT-3.4 passam |

---

## Artefatos de Evidência (Forensic Chain of Custody)

1. Output de `make test-db` — 2/2 testes ok em `banned_until_infinity_regression_test.sql`
2. Output de `make test-e2e-file FILE=test/integration/e2e/superadmin/ct13_unarchive_organization_cascade_test.dart` — 7/7 ok
3. Resultado de `SELECT COUNT(*) FROM auth.users WHERE banned_until = 'infinity'::timestamptz` — `0` após migração
4. `pg_proc.prosrc` de `super_admin_archive_organization` — ausência de literal `'infinity'`

Estes artefatos constituem a prova documental que a migração foi validada segundo os padrões de governança VeraProb e podem ser referenciados em auditorias contratuais futuras.
