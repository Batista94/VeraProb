# Forensic Test Plan — Migration `20260708000003_check_schema_integrity_rpc`

> **Classificação:** Engineering Study / Forensic Audit
> **Emitido por:** QA/Security + Senior Engineer Council Personas
> **Data de emissão:** 2026-07-08
> **Migração alvo:** `supabase/migrations/20260708000003_check_schema_integrity_rpc.sql`
> **Objeto criado:** `public.check_schema_integrity(p_org_id UUID)` (FUNCTION SECURITY DEFINER)
> **Consumidores:** Edge Function `super-admin-proxy` (action `check_schema_integrity`, linha 306); Dart `SupabaseSuperAdminRepository.checkSchemaIntegrity`; `_checkIntegrity()` em `tenant_health_tab.dart`
> **Invariantes cobertos:** INV-1 (org_id scoping), INV-3 (organizations não é ledger — UPDATE permitido), INV-6 (UTC: `NOW() AT TIME ZONE 'UTC'`), INV-7 (JSONB tipado), INV-22 (EXECUTE apenas para service_role), INV-DB (UPDATE single-row por PK — sem bloqueio)

---

## Contexto da Investigação

A Edge Function `super-admin-proxy` roteava a ação `check_schema_integrity` para um RPC que nunca existiu. O PostgREST retornava `42883 — function check_schema_integrity(uuid) does not exist`, capturado pelo outer catch da edge e devolvido como `{error: "Internal server error"}` HTTP 500 ao Flutter. O botão "Verificar Integridade" no painel `Saúde Técnica` era completamente inoperante.

Esta migração cria o RPC com SECURITY DEFINER para permitir leitura de `information_schema.tables` e UPDATE em `public.organizations` bypassando RLS. O RPC deriva o status de integridade contando quantas das 4 tabelas críticas (`contracts`, `canonical_facts`, `operational_alerts`, `user_roles`) existem no schema `public`, atualiza as três colunas adicionadas pela migração `20260708000001`, e retorna JSONB com os campos exatos esperados por `TenantTechnicalHealthView.fromJson`.

O RPC é acessível exclusivamente por `service_role` (Edge Function com service_key). A autenticação do super_admin é validada upstream pelo proxy antes de rotear para este RPC.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|---|---|
| PostgreSQL | ≥ 14 |
| Tabela `public.organizations` | Presente com colunas `schema_integrity_status`, `schema_version`, `last_schema_check_at` (migração `20260708000001`) |
| VIEW `super_admin_tenant_technical_health_view` | Presente (migração `20260708000002`) |
| Tabelas críticas esperadas | `contracts`, `canonical_facts`, `operational_alerts`, `user_roles` todas presentes |
| Role `service_role` | Disponível para teste de execução |
| Ambiente de teste | Supabase local (`supabase start`) ou staging isolado |
| Migração `20260708000003` | Aplicada com sucesso |

---

## Grupo 1 — Existência e Assinatura da Função (INV-7)

### Objetivo

Confirmar que a função existe com a assinatura correta, linguagem, SECURITY DEFINER, e search_path seguro.

---

### CT-FN-01: Função Existe com Assinatura Correta

**Hipótese forense:** A função `check_schema_integrity` existe em `public`, aceita exatamente um parâmetro `UUID`, e retorna `JSONB`.

```sql
SELECT
  p.proname           AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid)    AS return_type,
  p.prosecdef         AS security_definer,
  p.provolatile       AS volatility
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'check_schema_integrity';
```

**Critério de aceitação:**

| function_name | arguments | return_type | security_definer | volatility |
|---|---|---|---|---|
| check_schema_integrity | p_org_id uuid | jsonb | true | v |

**Critério de falha:** Função ausente (`ERROR 42883` na edge) ou `security_definer = false` (RPC não conseguiria ler `information_schema` ou atualizar `organizations` sem RLS bypass).

---

### CT-FN-02: Permissões Restritas a `service_role` (INV-22)

**Hipótese forense:** Apenas `service_role` pode executar a função. `authenticated` e `PUBLIC` devem ter EXECUTE revogado.

```sql
SELECT
  grantee,
  privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND routine_name    = 'check_schema_integrity'
ORDER BY grantee;
```

**Critério de aceitação:** Exatamente uma linha — `grantee = 'service_role'`, `privilege_type = 'EXECUTE'`. Nenhuma entrada para `PUBLIC` ou `authenticated`.

**Critério de falha:** Qualquer linha extra é falha crítica de INV-22 — um tenant autenticado poderia triggerar verificação de integridade de qualquer org e disparar UPDATEs em `organizations`.

---

### CT-FN-03: Tentativa de Execução como `authenticated` é Bloqueada (INV-22)

**Hipótese forense:** Confirmação dinâmica — sessão como `authenticated` deve receber `permission denied`.

```sql
SET ROLE authenticated;

-- DEVE FALHAR com: ERROR 42501: permission denied for function check_schema_integrity
SELECT public.check_schema_integrity('00000000-0000-0000-0000-000000000001'::UUID);

RESET ROLE;
```

**Critério de aceitação:** `ERROR 42501: permission denied for function check_schema_integrity`.

**Critério de falha:** Função executa. Falha crítica de INV-22 — escalação imediata para QA/Sec.

---

## Grupo 2 — Lógica de Derivação de Status (INV-7)

### Objetivo

Verificar que os três valores de `schema_integrity_status` são derivados corretamente a partir do número de tabelas críticas presentes, e que o JSONB retornado contém exatamente os campos esperados por `TenantTechnicalHealthView.fromJson`.

---

### CT-LG-01: Schema Completo → `compliant` (4/4 tabelas)

**Hipótese forense:** Com todas as 4 tabelas críticas presentes no schema `public` (condição normal de produção), o RPC retorna `schema_integrity_status = 'compliant'`.

**Pré-condição:** As tabelas `contracts`, `canonical_facts`, `operational_alerts`, `user_roles` existem (verificáveis via migração base).

```sql
-- Usar uma org existente
DO $$
DECLARE
  v_org_id UUID;
  v_result JSONB;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  v_result := public.check_schema_integrity(v_org_id);
  RAISE NOTICE 'Result: %', v_result;

  -- Asserção inline
  IF (v_result->>'schema_integrity_status') <> 'compliant' THEN
    RAISE EXCEPTION 'FAIL CT-LG-01: expected compliant, got %',
      v_result->>'schema_integrity_status';
  END IF;
END $$;
```

**Critério de aceitação:** RAISE NOTICE exibe `"schema_integrity_status": "compliant"` sem RAISE EXCEPTION.

**Critério de falha:** Status diferente de `compliant` indica que o FOREACH não está contando tabelas existentes corretamente, ou que `information_schema.tables` não está visível para o SECURITY DEFINER com `search_path = public, information_schema`.

---

### CT-LG-02: JSONB Retornado Contém Exatamente 3 Campos

**Hipótese forense:** O JSONB de retorno contém exatamente `schema_integrity_status`, `schema_version`, e `last_check_at` — os três campos consumidos por `TenantTechnicalHealthView.fromJson`.

```sql
DO $$
DECLARE
  v_org_id UUID;
  v_result JSONB;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  v_result := public.check_schema_integrity(v_org_id);

  -- Verificar presença dos 3 campos
  IF v_result->>'schema_integrity_status' IS NULL THEN
    RAISE EXCEPTION 'FAIL CT-LG-02: missing schema_integrity_status';
  END IF;
  IF v_result->>'schema_version' IS NULL THEN
    RAISE EXCEPTION 'FAIL CT-LG-02: missing schema_version';
  END IF;
  IF v_result->>'last_check_at' IS NULL THEN
    RAISE EXCEPTION 'FAIL CT-LG-02: missing last_check_at (nullable in Dart — should be present in JSONB as ISO string)';
  END IF;

  RAISE NOTICE 'CT-LG-02 PASS: %', v_result;
END $$;
```

**Critério de aceitação:** Todos os 3 campos presentes. `last_check_at` é string ISO 8601 UTC (e.g. `"2026-07-08T12:00:00+00:00"`).

**Critério de falha:** Campo ausente → `TenantTechnicalHealthView.fromJson` recebe null onde não esperado; `last_check_at` sem offset timezone → violação de INV-6.

---

### CT-LG-03: `schema_version` Preservada se Já Calculada

**Hipótese forense:** Se `organizations.schema_version` já tem um valor diferente de `'unknown'`, o RPC não sobrescreve com a data atual — preserva o valor existente.

```sql
DO $$
DECLARE
  v_org_id UUID;
  v_result JSONB;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;

  -- Setar versão arbitrária diferente de 'unknown'
  UPDATE public.organizations
     SET schema_version = '2025-01-15'
   WHERE id = v_org_id;

  v_result := public.check_schema_integrity(v_org_id);

  IF (v_result->>'schema_version') <> '2025-01-15' THEN
    RAISE EXCEPTION 'FAIL CT-LG-03: expected schema_version preserved as 2025-01-15, got %',
      v_result->>'schema_version';
  END IF;

  RAISE NOTICE 'CT-LG-03 PASS: schema_version preserved as %', v_result->>'schema_version';
END $$;
```

**Critério de aceitação:** `schema_version = '2025-01-15'` (valor preservado, não sobrescrito com data de hoje).

**Critério de falha:** `schema_version` substituída por data atual — lógica `COALESCE(NULLIF(..., 'unknown'), ...)` quebrada.

---

### CT-LG-04: `schema_version` Calculada se Era `'unknown'`

**Hipótese forense:** Se `organizations.schema_version = 'unknown'`, o RPC deriva a versão como `YYYY-MM-DD` (data UTC atual).

```sql
DO $$
DECLARE
  v_org_id UUID;
  v_result JSONB;
  v_expected_date TEXT;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;

  -- Resetar para 'unknown'
  UPDATE public.organizations
     SET schema_version = 'unknown'
   WHERE id = v_org_id;

  v_expected_date := to_char(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD');
  v_result := public.check_schema_integrity(v_org_id);

  IF (v_result->>'schema_version') <> v_expected_date THEN
    RAISE EXCEPTION 'FAIL CT-LG-04: expected %, got %',
      v_expected_date, v_result->>'schema_version';
  END IF;

  RAISE NOTICE 'CT-LG-04 PASS: schema_version calculated as %', v_result->>'schema_version';
END $$;
```

**Critério de aceitação:** `schema_version = YYYY-MM-DD` (data UTC atual, e.g. `'2026-07-08'`).

**Critério de falha:** `schema_version = 'unknown'` → COALESCE não funcionando; data em timezone local → violação de INV-6.

---

## Grupo 3 — Persistência em `organizations` (INV-3, INV-6)

### Objetivo

Verificar que o RPC efetivamente atualiza as três colunas em `organizations` e que o timestamp usa UTC.

---

### CT-PS-01: UPDATE em `organizations` Persiste Após RPC

**Hipótese forense:** Após `check_schema_integrity`, as colunas `schema_integrity_status`, `schema_version`, `last_schema_check_at` em `organizations` refletem os valores retornados no JSONB.

```sql
DO $$
DECLARE
  v_org_id UUID;
  v_result JSONB;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;

  -- Resetar para estado inicial
  UPDATE public.organizations
     SET schema_integrity_status = 'unknown',
         schema_version          = 'unknown',
         last_schema_check_at    = NULL
   WHERE id = v_org_id;

  v_result := public.check_schema_integrity(v_org_id);
END $$;

-- Verificar persistência
SELECT
  schema_integrity_status,
  schema_version,
  last_schema_check_at
FROM public.organizations
WHERE schema_integrity_status <> 'unknown'
   OR schema_version          <> 'unknown'
   OR last_schema_check_at    IS NOT NULL
LIMIT 5;
```

**Critério de aceitação:** Pelo menos uma linha mostrando `schema_integrity_status = 'compliant'` (ou status derivado), `schema_version` com data, `last_schema_check_at` não nulo.

**Critério de falha:** Nenhuma linha — UPDATE não persistiu (SECURITY DEFINER não tem permissão de escrita, ou p_org_id não corresponde a nenhuma linha).

---

### CT-PS-02: `last_schema_check_at` Salvo em UTC (INV-6)

**Hipótese forense:** O timestamp persistido em `last_schema_check_at` usa UTC (offset `+00`), não o timezone do servidor.

```sql
DO $$
DECLARE v_org_id UUID;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  PERFORM public.check_schema_integrity(v_org_id);
END $$;

-- Verificar timezone do timestamp
SELECT
  last_schema_check_at,
  last_schema_check_at AT TIME ZONE 'UTC' AS in_utc,
  EXTRACT(TIMEZONE FROM last_schema_check_at) AS offset_seconds
FROM public.organizations
WHERE last_schema_check_at IS NOT NULL
LIMIT 1;
```

**Critério de aceitação:** `offset_seconds = 0` (UTC). O valor `in_utc` é idêntico ao `last_schema_check_at` bruto.

**Critério de falha:** `offset_seconds <> 0` → `NOW() AT TIME ZONE 'UTC'` não está sendo usado corretamente — violação de INV-6.

---

### CT-PS-03: VIEW Atualizada Imediatamente Após RPC (INV-6)

**Hipótese forense:** Como a VIEW é uma VIEW regular (não MV), ela reflete o estado atual de `organizations` imediatamente após o UPDATE do RPC. `last_check_at` na VIEW corresponde a `last_schema_check_at` em `organizations`.

```sql
DO $$
DECLARE
  v_org_id UUID;
BEGIN
  SELECT id INTO v_org_id FROM public.organizations LIMIT 1;
  PERFORM public.check_schema_integrity(v_org_id);
END $$;

-- Verificar VIEW reflete atualização imediata
SELECT
  v.schema_integrity_status,
  v.schema_version,
  v.last_check_at
FROM public.super_admin_tenant_technical_health_view v
JOIN public.organizations o ON o.id = v.id
WHERE o.last_schema_check_at IS NOT NULL
LIMIT 1;
```

**Critério de aceitação:** `last_check_at` na VIEW não é NULL e corresponde ao timestamp do UPDATE. `schema_integrity_status` e `schema_version` na VIEW correspondem ao que o RPC persistiu.

**Critério de falha:** `last_check_at = NULL` na VIEW mesmo após RPC → alias `last_schema_check_at AS last_check_at` incorreto na VIEW (migração `000002`).

---

## Grupo 4 — Integração com Edge Function (INV-1)

### Objetivo

Validar que após a migração o botão "Verificar Integridade" no painel SuperAdmin produz HTTP 200 e atualiza a VIEW em tempo real.

---

### CT-INT-01: Edge `check_schema_integrity` Responde 200

**Procedimento:**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/super-admin-proxy \
  -H "Authorization: Bearer $SUPABASE_SUPER_ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d "{
    \"action\": \"check_schema_integrity\",
    \"params\": { \"organization_id\": \"$(psql -At -c 'SELECT id FROM public.organizations LIMIT 1' $DATABASE_URL)\" }
  }"
```

**Critério de aceitação:** HTTP 200 com body `{"data": {"schema_integrity_status": "compliant", "schema_version": "2026-07-08", "last_check_at": "..."}}`. Log do Edge não exibe `42883` nem `42501`.

**Critério de falha:** HTTP 500 com `{error: "Internal server error"}` e `42883 — function check_schema_integrity(uuid) does not exist` no log → migração não aplicada ou schema cache desatualizado.

---

### CT-INT-02: Sequência Completa — `get_tenant_technical_health` Após `check_schema_integrity`

**Hipótese forense:** Após acionar `check_schema_integrity`, a subsequente chamada a `get_tenant_technical_health` retorna `last_check_at` não nulo e `schema_integrity_status = 'compliant'`, confirmando que o UPDATE na VIEW é imediato.

**Procedimento:**

```bash
ORG_ID=$(psql -At -c 'SELECT id FROM public.organizations LIMIT 1' $DATABASE_URL)

# 1. Acionar verificação
curl -s -X POST http://127.0.0.1:54321/functions/v1/super-admin-proxy \
  -H "Authorization: Bearer $SUPABASE_SUPER_ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"check_schema_integrity\", \"params\": {\"organization_id\": \"$ORG_ID\"}}"

# 2. Buscar saúde técnica atualizada
curl -s -X POST http://127.0.0.1:54321/functions/v1/super-admin-proxy \
  -H "Authorization: Bearer $SUPABASE_SUPER_ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"get_tenant_technical_health\", \"params\": {\"organization_id\": \"$ORG_ID\"}}"
```

**Critério de aceitação:** Segundo curl retorna `{"data": {"schema_integrity_status": "compliant", "last_check_at": "<não nulo>", ...}}`. `replication_status` reflete telemetria da org (não o RPC).

**Critério de falha:** `last_check_at` ainda `null` após verificação → alias da VIEW incorreto ou UPDATE não persistiu (CT-PS-01 falharia antes).

---

## Grupo 5 — Idempotência e Zero-Downtime (INV-DB)

### Objetivo

Confirmar que a migração pode ser re-executada (OR REPLACE) e que a função não bloqueia tabelas.

---

### CT-ID-01: Re-execução Sem Erro (CREATE OR REPLACE)

**Hipótese forense:** `CREATE OR REPLACE FUNCTION` permite re-execução sem `ERROR 42723: function already exists`.

**Procedimento:** Executar o arquivo SQL da migração duas vezes consecutivas em ambiente local.

**Critério de aceitação:** Segunda execução completa sem erro. `pg_proc` ainda tem exatamente uma linha para `check_schema_integrity` em schema `public`.

**Critério de falha:** `ERROR 42723` — indica que a assinatura foi alterada entre execuções (impossível por design, mas validável).

---

### CT-ID-02: GRANT/REVOKE Idempotentes

**Hipótese forense:** Re-executar a migração não duplica grants nem gera erro em `REVOKE` de privilege que já foi revogado.

**Procedimento:** Executar o bloco de grants isoladamente três vezes.

**Critério de aceitação:** Nenhum erro em nenhuma execução. `information_schema.routine_privileges` ainda mostra exatamente uma linha (`service_role EXECUTE`).

---

## Matriz de Rastreabilidade

| Caso de Teste | Invariante | Tipo | Automatizável | Prioridade |
|---|---|---|---|---|
| CT-FN-01 | INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-FN-02 | INV-22 | Permission Audit | Sim (CI) | P0 - Bloqueante |
| CT-FN-03 | INV-22 | Red Team | Sim (CI) | P0 - Bloqueante |
| CT-LG-01 | INV-7 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-LG-02 | INV-7 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-LG-03 | INV-3 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-LG-04 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-PS-01 | INV-3 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-PS-02 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-PS-03 | INV-6 | Integration | Sim (CI) | P0 - Bloqueante |
| CT-INT-01 | INV-1 | Integration | Sim (CI) | P0 - Bloqueante |
| CT-INT-02 | INV-1 | Integration | Sim (CI) | P0 - Bloqueante |
| CT-ID-01 | INV-DB | Idempotency | Manual | P1 |
| CT-ID-02 | INV-DB | Idempotency | Manual | P1 |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 - Bloqueante** devem passar antes do merge. Falha em qualquer P0 é **VETO automático** pelo Reviewer Persona.

| Gate | Condição |
|---|---|
| **PASS** | CT-FN-01/02/03 confirmam existência e permissões; CT-LG-01..04 confirmam lógica de derivação e preservação de versão; CT-PS-01..03 confirmam persistência UTC e reflexo imediato na VIEW; CT-INT-01/02 confirmam pipeline end-to-end sem `42883` |
| **VETO** | CT-FN-02/03 (authenticated pode executar), CT-PS-02 (`last_schema_check_at` em timezone local — INV-6), CT-LG-01 (tabelas críticas não contadas corretamente) |
| **WARN** | CT-ID-01/02 — úteis mas não bloqueiam merge se justificado |

---

## Pós-Apply Checklist (Operador)

1. [ ] `supabase db reset` em local — migrações `000001` + `000002` + `000003` aplicam sem erro em sequência
2. [ ] `bash scripts/sync_db_types.sh` — `supabase/types.database.ts` regenerado e commitado (H-02)
3. [ ] `bash scripts/refresh_schema_cache.sh` — PostgREST vê o novo RPC (H-09)
4. [ ] CT-FN-01 verificado manualmente (`security_definer = true`)
5. [ ] CT-INT-01 executado — HTTP 200 confirmado sem `42883` no log do Edge
6. [ ] CT-INT-02 executado — VIEW atualizada imediatamente após `check_schema_integrity`
7. [ ] Aba `Saúde Técnica` testada manualmente: botão "Verificar Integridade" retorna sem `DomainException`

---

## Artefatos de Evidência (Forensic Chain of Custody)

1. **Output** de CT-FN-01: `pg_proc` com `security_definer = true` e `return_type = jsonb`
2. **Output** de CT-FN-02: `routine_privileges` com exatamente `service_role EXECUTE`
3. **Output** de CT-LG-01: RAISE NOTICE confirmando `schema_integrity_status = 'compliant'`
4. **Output** de CT-LG-02: JSONB com todos os 3 campos presentes
5. **Output** de CT-PS-02: `offset_seconds = 0` confirmando UTC
6. **Log** do Edge Function durante CT-INT-01: ausência de `42883`/`42501`
7. **Output** de CT-INT-02: `last_check_at` não nulo após sequência completa
