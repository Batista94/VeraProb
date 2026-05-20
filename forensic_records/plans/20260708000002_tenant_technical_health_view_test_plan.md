# Forensic Test Plan — Migration `20260708000002_tenant_technical_health_view`

> **Classificação:** Engineering Study / Forensic Audit
> **Emitido por:** QA/Security + Senior Engineer Council Personas
> **Data de emissão:** 2026-07-08
> **Migração alvo:** `supabase/migrations/20260708000002_tenant_technical_health_view.sql`
> **Objeto criado:** `public.super_admin_tenant_technical_health_view` (VIEW)
> **Consumidores:** Edge Function `super-admin-proxy` (action `get_tenant_technical_health`, linha 277); Riverpod provider de saúde técnica; Dart view model `TenantTechnicalHealthView`
> **Invariantes cobertos:** INV-1 (org_id scoping na edge), INV-6 (UTC — thresholds de replicação), INV-7 (tipos estritos), INV-22 (isolamento tenant — service_role only), INV-DB (zero-downtime — DROP/CREATE VIEW sem bloqueio)

---

## Contexto da Investigação

A Edge Function `super-admin-proxy` chamava `.from("super_admin_tenant_technical_health_view")` desde a introdução do painel de saúde técnica SuperAdmin, mas **a VIEW nunca foi criada** (`grep -r "super_admin_tenant_technical_health_view" supabase/migrations/` retornava vazio). A falha se manifestava como `PostgREST 42P01 — relation does not exist` na ação `get_tenant_technical_health`, cascateando em `{error: "Internal server error"}` HTTP 500 no Flutter → `DomainException` no provider.

Esta migração cria a VIEW com `security_invoker = true`, seguindo o mesmo padrão da `super_admin_tenant_health_view` (`20260520180001`). A VIEW expõe exatamente 5 colunas contratadas com `TenantTechnicalHealthView.fromJson`: `id`, `replication_status`, `schema_integrity_status`, `schema_version`, `last_check_at`. O `replication_status` é derivado de `MAX(canonical_facts.gps_timestamp)` comparado a thresholds UTC — healthy/delayed/failed/unknown — mapeando para os valores do enum Dart `ReplicationStatus`.

A VIEW não possui RLS (VIEWs com `security_invoker = true` herdam RLS das tabelas base — mas como o acesso ocorre via service_role na edge, que bypassa RLS, isso é intencional). A isolação cross-tenant é garantida pela edge function que sempre filtra `.eq("id", orgId)`.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|---|---|
| PostgreSQL | ≥ 14 |
| Tabela `public.organizations` | Presente com colunas da migração `20260708000001` |
| Tabela `public.canonical_facts` | Presente (contém `gps_timestamp`, `organization_id`) |
| Migração `20260708000001` | Aplicada antes desta |
| Role `service_role` | Disponível para teste de leitura |
| Ambiente de teste | Supabase local (`supabase start`) ou staging isolado |

---

## Grupo 1 — Estrutura e Permissões (INV-7, INV-22)

### Objetivo

Confirmar que a VIEW existe com exatamente 5 colunas nos tipos corretos, e que apenas `service_role` pode consultá-la.

---

### CT-ST-01: VIEW Criada com Schema Correto (5 Colunas)

**Hipótese forense:** A VIEW expõe exatamente as colunas contratadas com `TenantTechnicalHealthView.fromJson`: `id UUID`, `replication_status TEXT`, `schema_integrity_status TEXT`, `schema_version TEXT`, `last_check_at TIMESTAMPTZ`.

```sql
SELECT
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'super_admin_tenant_technical_health_view'
ORDER BY ordinal_position;
```

**Critério de aceitação:**

| column_name | data_type |
|---|---|
| id | uuid |
| replication_status | text |
| schema_integrity_status | text |
| schema_version | text |
| last_check_at | timestamp with time zone |

**Critério de falha:** Coluna ausente, nome divergente (e.g. `last_schema_check_at` em vez de `last_check_at` — quebraria `TenantTechnicalHealthView.fromJson`), tipo incorreto (e.g. `timestamp without time zone` viola INV-6), ou coluna extra inesperada.

---

### CT-ST-02: VIEW é do Tipo VIEW (não MV)

**Hipótese forense:** O objeto deve ser uma VIEW regular (não MATERIALIZED VIEW), pois `replication_status` é calculado dinamicamente (sem refresh explícito).

```sql
SELECT table_type
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name   = 'super_admin_tenant_technical_health_view';
```

**Critério de aceitação:** Uma linha retornada (a tabela `information_schema.views` só contém VIEWs, não MVs).

**Critério de falha:** Zero linhas — objeto foi criado como MATERIALIZED VIEW ou não existe.

---

### CT-ST-03: Permissões Travadas para `service_role` (INV-22)

**Hipótese forense:** A VIEW não tem RLS própria — a barreira de isolamento é o `GRANT SELECT` exclusivo para `service_role`. Roles `anon` e `authenticated` devem ter `permission denied`.

```sql
SELECT
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name   = 'super_admin_tenant_technical_health_view'
ORDER BY grantee, privilege_type;
```

**Critério de aceitação:** Exatamente uma linha — `grantee = 'service_role'`, `privilege_type = 'SELECT'`. Nenhuma entrada para `PUBLIC`, `anon`, ou `authenticated`.

**Critério de falha:** Qualquer linha extra é falha crítica de INV-22 (tenant-A poderia ler saúde técnica de tenant-B).

---

### CT-ST-04: Tentativa de Leitura como `authenticated` é Bloqueada (INV-22)

**Hipótese forense:** Confirmação dinâmica — uma sessão como `authenticated` deve receber `permission denied`.

```sql
SET ROLE authenticated;

-- DEVE FALHAR com: ERROR 42501: permission denied for view super_admin_tenant_technical_health_view
SELECT * FROM public.super_admin_tenant_technical_health_view LIMIT 1;

RESET ROLE;
```

**Critério de aceitação:** `ERROR 42501: permission denied for view super_admin_tenant_technical_health_view`.

**Critério de falha:** Query retorna linhas. Falha crítica de INV-22 — escalação imediata para QA/Sec.

---

## Grupo 2 — Lógica de `replication_status` (INV-6)

### Objetivo

Verificar que os quatro valores de `replication_status` (healthy/delayed/failed/unknown) são derivados corretamente usando thresholds UTC, mapeando para o enum Dart `ReplicationStatus`.

---

### CT-RP-01: `replication_status = 'healthy'` (telemetria recente)

**Hipótese forense:** Org com `MAX(gps_timestamp)` nos últimos 5 minutos deve retornar `healthy`.

**Setup:**

```sql
-- Org de teste com telemetria recente
DO $$
DECLARE v_org_id UUID := '00000000-0000-0000-0000-00000000aa01'::UUID;
BEGIN
  INSERT INTO public.organizations (id, name, legal_name)
  VALUES (v_org_id, 'Org Healthy', 'Org Healthy Legal')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.canonical_facts (organization_id, gps_timestamp, asset_id, raw_payload_hash)
  VALUES (
    v_org_id,
    NOW() AT TIME ZONE 'UTC' - INTERVAL '2 minutes',
    gen_random_uuid(),
    repeat('a', 64)
  );
END $$;
```

**Verificação:**

```sql
SELECT replication_status
FROM public.super_admin_tenant_technical_health_view
WHERE id = '00000000-0000-0000-0000-00000000aa01'::UUID;
```

**Critério de aceitação:** `replication_status = 'healthy'`.

**Critério de falha:** Valor diferente indica que o threshold `NOW() AT TIME ZONE 'UTC' - INTERVAL '5 minutes'` está usando timezone local (violação de INV-6).

---

### CT-RP-02: `replication_status = 'delayed'` (telemetria entre 5 min e 1 hora)

**Hipótese forense:** Org com último `gps_timestamp` há 30 minutos deve retornar `delayed`.

**Setup:**

```sql
DO $$
DECLARE v_org_id UUID := '00000000-0000-0000-0000-00000000aa02'::UUID;
BEGIN
  INSERT INTO public.organizations (id, name, legal_name)
  VALUES (v_org_id, 'Org Delayed', 'Org Delayed Legal')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.canonical_facts (organization_id, gps_timestamp, asset_id, raw_payload_hash)
  VALUES (
    v_org_id,
    NOW() AT TIME ZONE 'UTC' - INTERVAL '30 minutes',
    gen_random_uuid(),
    repeat('b', 64)
  );
END $$;
```

**Verificação:**

```sql
SELECT replication_status
FROM public.super_admin_tenant_technical_health_view
WHERE id = '00000000-0000-0000-0000-00000000aa02'::UUID;
```

**Critério de aceitação:** `replication_status = 'delayed'`.

**Critério de falha:** `'healthy'` indica boundary incorreto; `'failed'` indica que a condição de `INTERVAL '1 hour'` não está sendo avaliada.

---

### CT-RP-03: `replication_status = 'failed'` (telemetria > 1 hora)

**Hipótese forense:** Org com último `gps_timestamp` há mais de 1 hora deve retornar `failed`.

**Setup:**

```sql
DO $$
DECLARE v_org_id UUID := '00000000-0000-0000-0000-00000000aa03'::UUID;
BEGIN
  INSERT INTO public.organizations (id, name, legal_name)
  VALUES (v_org_id, 'Org Failed', 'Org Failed Legal')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.canonical_facts (organization_id, gps_timestamp, asset_id, raw_payload_hash)
  VALUES (
    v_org_id,
    NOW() AT TIME ZONE 'UTC' - INTERVAL '2 hours',
    gen_random_uuid(),
    repeat('c', 64)
  );
END $$;
```

**Verificação:**

```sql
SELECT replication_status
FROM public.super_admin_tenant_technical_health_view
WHERE id = '00000000-0000-0000-0000-00000000aa03'::UUID;
```

**Critério de aceitação:** `replication_status = 'failed'`.

**Critério de falha:** `'delayed'` indica que o CASE não está avaliando o ELSE corretamente.

---

### CT-RP-04: `replication_status = 'unknown'` (org sem telemetria)

**Hipótese forense:** Org sem nenhum `canonical_fact` (LEFT JOIN retorna NULL) deve retornar `unknown`.

**Setup:**

```sql
INSERT INTO public.organizations (id, name, legal_name)
VALUES ('00000000-0000-0000-0000-00000000aa04'::UUID, 'Org Unknown', 'Org Unknown Legal')
ON CONFLICT (id) DO NOTHING;
-- Não inserir nada em canonical_facts para esta org
```

**Verificação:**

```sql
SELECT replication_status
FROM public.super_admin_tenant_technical_health_view
WHERE id = '00000000-0000-0000-0000-00000000aa04'::UUID;
```

**Critério de aceitação:** `replication_status = 'unknown'`. Confirma que `MAX(cf.gps_timestamp) IS NULL` → `'unknown'` e que o `TenantTechnicalHealthView.fromJson` resolverá para `ReplicationStatus.unknown`.

**Critério de falha:** `'failed'` indica que a condição `IS NULL` não está sendo avaliada antes do `ELSE`.

---

## Grupo 3 — Isolamento Cross-Tenant (INV-1, INV-22)

### Objetivo

Verificar que a VIEW, em conjunto com o filtro da edge function (`.eq("id", orgId)`), não vaza dados de uma org para outra.

---

### CT-IS-01: Filtro por `id` Retorna Exatamente Uma Org

**Hipótese forense:** A VIEW expõe dados de todas as orgs (GROUP BY `o.id`), mas a edge function sempre filtra por `orgId`. Uma query sem filtro retorna N linhas; com filtro por UUID específico, retorna exatamente 1 ou 0.

```sql
-- Com filtro (simula edge function)
SELECT COUNT(*) AS row_count
FROM public.super_admin_tenant_technical_health_view
WHERE id = '00000000-0000-0000-0000-00000000aa01'::UUID;
```

**Critério de aceitação:** `row_count = 1`. A VIEW não retorna dados de outras orgs quando filtrada.

**Critério de falha:** `row_count > 1` indicaria que o `GROUP BY o.id` está incompleto (impossível por design — mas valida que o GROUP BY funciona corretamente).

---

### CT-IS-02: Org A Não Vê Dados de Org B

**Hipótese forense:** Com duas orgs distintas com `replication_status` diferentes (healthy e failed), cada filtro por UUID retorna apenas o status da org correta.

```sql
SELECT
  id,
  replication_status
FROM public.super_admin_tenant_technical_health_view
WHERE id IN (
  '00000000-0000-0000-0000-00000000aa01'::UUID,
  '00000000-0000-0000-0000-00000000aa03'::UUID
)
ORDER BY id;
```

**Critério de aceitação:** Duas linhas — `aa01 = 'healthy'` e `aa03 = 'failed'`. Nenhum cruzamento de dados.

**Critério de falha:** `aa01` retornando `'failed'` indicaria que o `MAX()` aggregou `canonical_facts` de outras orgs (falha crítica de INV-22 — ausência do filtro `ON cf.organization_id = o.id`).

---

## Grupo 4 — Integração com Edge Function (INV-1)

### Objetivo

Validar que após a migração o pipeline completo (Edge Function → action `get_tenant_technical_health` → Dart) responde sem `PGRST205` e sem `DomainException`.

---

### CT-INT-01: Edge `get_tenant_technical_health` Responde 200

**Procedimento:**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/super-admin-proxy \
  -H "Authorization: Bearer $SUPABASE_SUPER_ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "get_tenant_technical_health",
    "params": { "organization_id": "00000000-0000-0000-0000-00000000aa01" }
  }'
```

**Critério de aceitação:** HTTP 200 com body `{"data": {"id": "...", "replication_status": "healthy", "schema_integrity_status": "unknown", "schema_version": "unknown", "last_check_at": null}}`. Log do Edge não exibe `PGRST205` nem `42P01`.

**Critério de falha:** HTTP 500 com `PGRST205 — relation "super_admin_tenant_technical_health_view" does not exist` — indica que migração não foi aplicada ou schema cache não foi refrescado (`bash scripts/refresh_schema_cache.sh`).

---

### CT-INT-02: Aba `Saúde Técnica` Renderiza Sem ErrorWidget

**Procedimento:**

```pwsh
make test-e2e-file FILE=test/integration/e2e/superadmin/tenant_detail_test.dart
```

**Critério de aceitação:** Testes da aba `Saúde Técnica` passam. `TenantTechnicalHealthView` é instanciado sem exceção. Provider não lança `DomainException`.

**Critério de falha:** `ErrorWidget` visível — diagnosticar com logs do Edge (`docker logs supabase_edge_runtime_veraprob`) para confirmar resolução do `42P01`.

---

## Matriz de Rastreabilidade

| Caso de Teste | Invariante | Tipo | Automatizável | Prioridade |
|---|---|---|---|---|
| CT-ST-01 | INV-6, INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-ST-02 | INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-ST-03 | INV-22 | Permission Audit | Sim (CI) | P0 - Bloqueante |
| CT-ST-04 | INV-22 | Red Team | Sim (CI) | P0 - Bloqueante |
| CT-RP-01 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-RP-02 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-RP-03 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-RP-04 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-IS-01 | INV-1 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-IS-02 | INV-22 | Red Team | Sim (CI) | P0 - Bloqueante |
| CT-INT-01 | INV-1 | Integration | Sim (CI) | P0 - Bloqueante |
| CT-INT-02 | n/a | E2E | Sim (CI) | P0 - Bloqueante |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 - Bloqueante** devem passar antes do merge. Falha em qualquer P0 é **VETO automático** pelo Reviewer Persona.

| Gate | Condição |
|---|---|
| **PASS** | CT-ST-01..04 verificam estrutura/permissões; CT-RP-01..04 confirmam os 4 valores de `replication_status` com boundaries UTC corretos; CT-IS-01/02 confirmam isolamento; CT-INT-01/02 confirmam pipeline end-to-end |
| **VETO** | CT-ST-03/04 (vazamento cross-tenant), CT-RP-01..04 (boundary UTC errado — INV-6), CT-IS-02 (org-A vê dados de org-B) |
| **WARN** | Latência de query > 500ms em org com > 1M canonical_facts (monitorar via EXPLAIN ANALYZE) |

---

## Pós-Apply Checklist (Operador)

1. [ ] `supabase db reset` em local — migrações `000001` + `000002` + `000003` aplicam sem erro
2. [ ] `bash scripts/sync_db_types.sh` — `supabase/types.database.ts` regenerado e commitado (H-02)
3. [ ] `bash scripts/refresh_schema_cache.sh` — PostgREST vê a nova VIEW (H-09)
4. [ ] CT-ST-01 verificado manualmente (5 colunas, tipos corretos)
5. [ ] CT-INT-01 executado — HTTP 200 confirmado

---

## Artefatos de Evidência (Forensic Chain of Custody)

1. **Output** de CT-ST-01: schema de colunas (5 linhas com tipos exatos)
2. **Output** de CT-ST-03: `role_table_grants` (apenas `service_role`)
3. **Output** de CT-RP-01..04: `replication_status` para cada cenário
4. **Output** de CT-IS-02: duas linhas com org-A e org-B sem cruzamento
5. **Log** do Edge Function durante CT-INT-01 (ausência de `PGRST205`/`42P01`)
