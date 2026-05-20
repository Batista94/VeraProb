# Forensic Test Plan — Migration `20260708000001_tenant_technical_health_columns`

> **Classificação:** Engineering Study / Forensic Audit
> **Emitido por:** QA/Security + Senior Engineer Council Personas
> **Data de emissão:** 2026-07-08
> **Migração alvo:** `supabase/migrations/20260708000001_tenant_technical_health_columns.sql`
> **Objeto criado:** Três colunas em `public.organizations` — `schema_integrity_status`, `schema_version`, `last_schema_check_at`
> **Consumidores:** Migração `20260708000002` (VIEW); Migração `20260708000003` (RPC); Dart view model `TenantTechnicalHealthView`
> **Invariantes cobertos:** INV-1 (org_id scoping), INV-3 (organizations não é ledger — UPDATE permitido), INV-6 (TIMESTAMPTZ mandatory), INV-7 (tipos estritos), INV-DB (zero-downtime — ADD COLUMN IF NOT EXISTS)

---

## Contexto da Investigação

A Edge Function `super-admin-proxy` e o Dart view model `TenantTechnicalHealthView` referenciavam campos de saúde técnica de schema (`schema_integrity_status`, `schema_version`, `last_check_at`) que nunca foram criados em nenhuma migração. A regressão se manifestava como `PGRST205 — relation "super_admin_tenant_technical_health_view" does not exist` na ação `get_tenant_technical_health`, que cascateava para `{error: "Internal server error"}` status 500 no Flutter.

Esta migração é o primeiro passo da cadeia de três migrações (`000001` → `000002` → `000003`) que resolve o gap. Ela adiciona as colunas de estado à tabela `organizations` de forma zero-downtime, usando `ADD COLUMN IF NOT EXISTS` com valores DEFAULT seguros (`'unknown'`) que garantem que orgs existentes não entrem em estado inválido. A coluna `last_schema_check_at` é nullable (nenhuma verificação ocorreu ainda), alinhada com a expectativa `lastCheckAt: null` no `TenantTechnicalHealthView.fromJson`.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|---|---|
| PostgreSQL | ≥ 14 |
| Tabela `public.organizations` | Presente (migração inicial) |
| Colunas `clock_drift_tolerance_s`, `data_retention_days` | Presentes (migração `20260520180000`) |
| Ambiente de teste | Supabase local (`supabase start`) ou staging isolado |
| Migração `20260708000001` | Aplicada com sucesso |

---

## Grupo 1 — Estrutura e Tipos de Coluna (INV-6, INV-7, INV-DB)

### Objetivo

Confirmar que as três colunas foram adicionadas com os tipos e defaults exatos esperados pelo contrato `TenantTechnicalHealthView.fromJson`.

---

### CT-SC-01: Colunas Presentes com Tipos Corretos

**Hipótese forense:** As três colunas existem em `public.organizations` com os tipos exatos: `schema_integrity_status TEXT NOT NULL`, `schema_version TEXT NOT NULL`, `last_schema_check_at TIMESTAMPTZ NULL`.

```sql
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'organizations'
  AND column_name  IN ('schema_integrity_status', 'schema_version', 'last_schema_check_at')
ORDER BY column_name;
```

**Critério de aceitação:**

| column_name | data_type | is_nullable | column_default |
|---|---|---|---|
| last_schema_check_at | timestamp with time zone | YES | NULL |
| schema_integrity_status | text | NO | 'unknown'::text |
| schema_version | text | NO | 'unknown'::text |

**Critério de falha:** Qualquer coluna ausente, tipo diferente (e.g. `character varying` em vez de `text`, `timestamp without time zone` violaria INV-6), nullable incorreto, ou default ausente. Falha indica regressão de INV-7.

---

### CT-SC-02: Constraint CHECK em `schema_integrity_status` Presente e Válida

**Hipótese forense:** O constraint `chk_schema_integrity_status` está presente e valida exatamente os valores `'compliant'`, `'minor_drift'`, `'critical_drift'`, `'unknown'`.

```sql
SELECT
  conname,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.organizations'::regclass
  AND conname  = 'chk_schema_integrity_status';
```

**Critério de aceitação:** Uma linha com `conname = 'chk_schema_integrity_status'` e `definition` contendo `'compliant'`, `'minor_drift'`, `'critical_drift'`, `'unknown'`.

**Critério de falha:** Constraint ausente — uma org poderia ter `schema_integrity_status = 'invalid_value'`, corrompendo o enum Dart.

---

### CT-SC-03: Constraint em Estado VALIDATED

**Hipótese forense:** O constraint foi validado (`VALIDATE CONSTRAINT`) — `convalidated = true`. Um constraint `NOT VALID` seria aceito na criação mas não aplicado em linhas existentes.

```sql
SELECT
  conname,
  convalidated
FROM pg_constraint
WHERE conrelid = 'public.organizations'::regclass
  AND conname  = 'chk_schema_integrity_status';
```

**Critério de aceitação:** `convalidated = true`.

**Critério de falha:** `convalidated = false` — constraint não protege linhas pré-existentes.

---

### CT-SC-04: Valor DEFAULT Aplicado em Orgs Existentes

**Hipótese forense:** Orgs criadas antes desta migração têm `schema_integrity_status = 'unknown'` e `schema_version = 'unknown'`, garantindo que o frontend não exiba estado inválido.

```sql
SELECT COUNT(*) AS orgs_without_default
FROM public.organizations
WHERE schema_integrity_status NOT IN ('compliant', 'minor_drift', 'critical_drift', 'unknown')
   OR schema_version IS NULL;
```

**Critério de aceitação:** `orgs_without_default = 0`.

**Critério de falha:** Qualquer valor fora do conjunto válido indica que o DEFAULT não foi aplicado retroativamente — violação de INV-7.

---

## Grupo 2 — Integridade de Dados (INV-3, INV-7)

### Objetivo

Verificar que INSERT e UPDATE respeitam o constraint e que orgs existentes continuam operacionais.

---

### CT-DT-01: INSERT com Valor Inválido é Rejeitado

**Hipótese forense:** Tentar inserir uma org com `schema_integrity_status = 'broken'` deve falhar com violação de constraint.

```sql
-- Deve falhar: ERROR 23514: new row for relation "organizations" violates check constraint
INSERT INTO public.organizations (
  id, name, legal_name, schema_integrity_status
)
VALUES (
  gen_random_uuid(),
  'Test Org',
  'Test Legal',
  'broken'
);
```

**Critério de aceitação:** `ERROR 23514` (check_violation). Nenhuma linha inserida.

**Critério de falha:** INSERT bem-sucedido com valor inválido — constraint não está ativo.

---

### CT-DT-02: UPDATE para Valor Válido Funciona (INV-3)

**Hipótese forense:** `organizations` não é ledger — UPDATE é permitido. O RPC `check_schema_integrity` deve conseguir atualizar as três colunas.

```sql
-- Usar uma org existente (ou a criada em CT-DT-01 com valor válido)
DO $$
DECLARE v_org_id UUID;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  IF v_org_id IS NOT NULL THEN
    UPDATE public.organizations
       SET schema_integrity_status = 'compliant',
           schema_version          = '2026-07-08',
           last_schema_check_at    = NOW() AT TIME ZONE 'UTC'
     WHERE id = v_org_id;
  END IF;
END $$;

-- Verificar o update
SELECT schema_integrity_status, schema_version, last_schema_check_at
FROM public.organizations
WHERE schema_integrity_status = 'compliant'
LIMIT 1;
```

**Critério de aceitação:** Retorna uma linha com `schema_integrity_status = 'compliant'`, `schema_version = '2026-07-08'`, `last_schema_check_at` não nulo em UTC.

**Critério de falha:** UPDATE falha (trigger de append-only indevido) ou `last_schema_check_at` em timezone local (violação de INV-6).

---

## Grupo 3 — Idempotência e Zero-Downtime (INV-DB)

### Objetivo

Confirmar que a migração pode ser re-executada sem erro e que não houve lock de tabela durante a adição das colunas.

---

### CT-ID-01: Re-execução da Migração Sem Erro

**Hipótese forense:** Todos os DDL usam `IF NOT EXISTS` / `OR REPLACE`. Re-executar o arquivo de migração não gera erro nem duplica constraints.

**Procedimento:** Executar o arquivo SQL da migração duas vezes consecutivas em ambiente local.

**Critério de aceitação:** Segunda execução completa sem erro. `pg_constraint` ainda tem exatamente uma linha para `chk_schema_integrity_status`.

**Critério de falha:** `ERROR 42710: constraint already exists` — indica que `ADD CONSTRAINT ... NOT VALID` foi usado sem verificação de existência prévia.

---

### CT-ID-02: ADD COLUMN Não Bloqueou Tabela

**Hipótese forense:** `ADD COLUMN IF NOT EXISTS` com `DEFAULT` constante no Postgres 11+ é uma operação de metadados — não reescreve a tabela e não toma `AccessExclusiveLock` prolongado.

**Verificação pós-migração em ambiente de teste com carga:**

```sql
-- Verificar que não há locks longos pendentes na tabela após a migração
SELECT pid, wait_event_type, wait_event, state, query_start, query
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
  AND query ILIKE '%organizations%';
```

**Critério de aceitação:** Zero linhas (sem locks pendentes). A migração concluiu sem bloquear operações concorrentes.

**Critério de falha:** Locks prolongados indicam que a operação se tornou bloqueante — escalação para INV-DB review.

---

## Matriz de Rastreabilidade

| Caso de Teste | Invariante | Tipo | Automatizável | Prioridade |
|---|---|---|---|---|
| CT-SC-01 | INV-6, INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-SC-02 | INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-SC-03 | INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-SC-04 | INV-7 | Data Assertion | Sim (CI) | P0 - Bloqueante |
| CT-DT-01 | INV-7 | Constraint Test | Sim (CI) | P0 - Bloqueante |
| CT-DT-02 | INV-3, INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-ID-01 | INV-DB | Idempotency | Manual | P1 |
| CT-ID-02 | INV-DB | Concurrency | Manual | P1 |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 - Bloqueante** devem passar antes do merge. Falha em qualquer P0 é **VETO automático** pelo Reviewer Persona.

| Gate | Condição |
|---|---|
| **PASS** | CT-SC-01..04 confirmam estrutura, tipos e defaults; CT-DT-01/02 confirmam constraint ativo e UPDATE permitido; cadeia `000002`/`000003` aplica sem erro |
| **VETO** | Coluna com tipo errado (especialmente `TIMESTAMP` sem `TZ` — violação de INV-6), constraint inativo, ou UPDATE rejeitado por trigger indevido |
| **WARN** | CT-ID-01/02 — úteis mas não bloqueiam merge se justificado |

---

## Pós-Apply Checklist (Operador)

1. [ ] `supabase db reset` em local — migração aplica sem erro (incluindo `000002` e `000003` em sequência)
2. [ ] `bash scripts/sync_db_types.sh` — `supabase/types.database.ts` regenerado e commitado (H-02)
3. [ ] `bash scripts/refresh_schema_cache.sh` — PostgREST vê as novas colunas (H-09)
4. [ ] Verificar CT-SC-01 manualmente com `psql` ou Supabase Studio
5. [ ] Confirmar que orgs existentes têm `schema_integrity_status = 'unknown'` (CT-SC-04)

---

## Artefatos de Evidência (Forensic Chain of Custody)

1. **Output** de CT-SC-01: lista das três colunas com tipos exatos
2. **Output** de CT-SC-02: definição do constraint `chk_schema_integrity_status`
3. **Output** de CT-SC-03: `convalidated = true`
4. **Output** de CT-SC-04: `orgs_without_default = 0`
5. **Output** de CT-DT-01: `ERROR 23514` confirmando constraint ativo
