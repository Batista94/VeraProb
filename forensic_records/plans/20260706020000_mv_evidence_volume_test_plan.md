# Forensic Test Plan — Migration `20260706020000_mv_evidence_volume`

> **Classificação:** Engineering Study / Forensic Audit
> **Emitido por:** QA/Security + Architect Council Personas
> **Data de emissão:** 2026-05-16
> **Migração alvo:** `supabase/migrations/20260706020000_mv_evidence_volume.sql`
> **Objeto criado:** `public.mv_evidence_volume` (MATERIALIZED VIEW)
> **Consumidores:** Edge Function `super-admin-proxy` (action `get_evidence_volume`); Riverpod provider `evidenceVolumeView`; Dart view model `EvidenceVolumeView`
> **Invariantes cobertos:** INV-1 (org_id partitioning), INV-6 (UTC), INV-7 (strict types — BIGINT counts), INV-15 (determinism — byte-identical replay), INV-22 (tenant isolation), INV-23 (free-tier compatible), INV-DB (zero-downtime)

---

## Contexto da Investigação

A Edge Function `super-admin-proxy` e o provider Riverpod `evidenceVolumeView` referenciavam a materialized view `public.mv_evidence_volume` desde a introdução do painel SuperAdmin de volumetria de evidência, mas **a MV nunca foi criada por nenhuma migration** (`grep -r "mv_evidence_volume" supabase/migrations/` retornou vazio). A regressão se manifestava como `PGRST205 — Could not find the table 'public.mv_evidence_volume' in the schema cache` durante a ação `get_evidence_volume` e cascateava como `ErrorWidget.builder was changed by the test` no E2E `adverse_scenarios_test.dart` cenário 8.1 (race condition de arquivamento).

Esta migração introduz a MV aplicando o contrato já assumido pelos consumidores: agregação `UNION ALL` das duas tabelas de evidência forense imutável (`justification_evidence_uploads` e `telegram_evidence_uploads`), agrupada por `organization_id`, com contagens histórica e mensal tipadas como `BIGINT`. Um índice único em `organization_id` habilita `REFRESH MATERIALIZED VIEW CONCURRENTLY`, agendado por `pg_cron` a cada 5 minutos em Supabase Cloud (com guard para dev local sem `pg_cron`).

A escolha de MV (em vez de VIEW regular ou RPC) é justificada pela natureza append-only de ambas as fontes — uma `VIEW` recalcularia `COUNT(*)` a cada request, escaneando potencialmente milhões de linhas; uma `RPC` agregadora teria o mesmo custo. A MV transforma o caminho de leitura em O(1) com latência aceitável de até 5 minutos (volumetria é informacional, não dispara ações financeiras).

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|---|---|
| PostgreSQL | ≥ 14 |
| Tabela `justification_evidence_uploads` | Presente (migração `20260502000001`) |
| Tabela `telegram_evidence_uploads` | Presente (migração `20260420000001`) |
| Extensão `pg_cron` | Opcional — presente em Supabase Cloud, ausente em local dev |
| Role `service_role` | Disponível para teste de leitura da MV |
| Ambiente de teste | Supabase local (`supabase start`) ou staging isolado |

---

## Grupo 1 — Estrutura e Permissões (INV-1, INV-7, INV-22)

### Objetivo

Confirmar que a MV foi criada com o schema esperado, que o índice único existe, e que apenas `service_role` tem permissão de leitura — impedindo que `anon`/`authenticated` consultem volumetria cross-tenant.

---

### CT-ST-01: MV Criada com Schema Correto

**Hipótese forense:** A MV expõe exatamente três colunas: `organization_id UUID`, `total_historical BIGINT`, `total_monthly BIGINT`.

```sql
-- RESULTADO ESPERADO: três colunas com tipos exatos
SELECT
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'mv_evidence_volume'
ORDER BY ordinal_position;
```

**Critério de aceitação:**

| column_name | data_type |
|---|---|
| organization_id | uuid |
| total_historical | bigint |
| total_monthly | bigint |

**Critério de falha:** Qualquer coluna ausente, tipo diferente (e.g. `integer` em vez de `bigint`), ou coluna extra inesperada. Falha indica regressão de INV-7.

---

### CT-ST-02: Índice Único Presente (habilita REFRESH CONCURRENTLY)

**Hipótese forense:** Sem um `UNIQUE INDEX` em `organization_id`, o pg_cron job falharia ao tentar `REFRESH CONCURRENTLY`, degradando para refresh bloqueante.

```sql
-- RESULTADO ESPERADO: uma linha, indisdef = true, indisunique = true
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename  = 'mv_evidence_volume';
```

**Critério de aceitação:** Uma única linha:
- `indexname = 'uq_mv_evidence_volume_org'`
- `indexdef` contém `CREATE UNIQUE INDEX` e `(organization_id)`

**Critério de falha:** Índice ausente ou não-único — bloqueia INV-DB (refresh sem CONCURRENTLY trava reads).

---

### CT-ST-03: Permissões Travadas para `service_role` (INV-1, INV-22)

**Hipótese forense:** A MV não tem RLS (MVs não herdam RLS no PostgreSQL). A única barreira de isolamento é o `GRANT SELECT` exclusivo para `service_role`. Roles `anon` e `authenticated` devem ter `permission denied`.

```sql
-- RESULTADO ESPERADO: apenas service_role com SELECT
SELECT
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name   = 'mv_evidence_volume'
ORDER BY grantee, privilege_type;
```

**Critério de aceitação:** Exatamente uma linha — `grantee = 'service_role'`, `privilege_type = 'SELECT'`. Nenhuma entrada para `PUBLIC`, `anon`, ou `authenticated`.

**Critério de falha:** Qualquer linha extra é falha crítica de INV-22 (tenant-A poderia ler contagem de tenant-B).

---

### CT-ST-04: Tentativa de Leitura como `authenticated` é Bloqueada

**Hipótese forense:** Confirmação dinâmica do GRANT — uma sessão como `authenticated` deve receber `permission denied` ao consultar a MV diretamente.

```sql
SET ROLE authenticated;

-- DEVE FALHAR com: ERROR 42501: permission denied for materialized view mv_evidence_volume
SELECT * FROM public.mv_evidence_volume LIMIT 1;

RESET ROLE;
```

**Critério de aceitação:** `ERROR 42501: permission denied for materialized view mv_evidence_volume`.

**Critério de falha:** Query retorna linhas. Falha crítica de INV-1/INV-22 — escalação imediata para QA/Sec.

---

## Grupo 2 — Agregação Correta (INV-6, INV-7, INV-15)

### Objetivo

Provar que a MV agrega corretamente o `UNION ALL` das duas fontes, que `total_monthly` respeita o boundary de mês em UTC, e que `REFRESH` produz estado byte-idêntico para o mesmo input (determinismo).

---

### CT-AG-01: Agregação Histórica `UNION ALL`

**Hipótese forense:** Inserindo N evidências para uma org através de ambas as fontes, `total_historical = N_just + N_tel` após `REFRESH`.

**Setup (executar como `service_role`):**

```sql
-- Inserir 3 evidências de justification
INSERT INTO public.justification_evidence_uploads (
  justification_id, organization_id, file_name, content_hash, storage_path
)
SELECT
  '00000000-0000-0000-0000-000000000001'::UUID,
  '00000000-0000-0000-0000-00000000aaaa'::UUID,
  'just_' || g || '.pdf',
  repeat('0', 64),
  'org-aaaa/just/' || g || '.pdf'
FROM generate_series(1, 3) g;

-- Inserir 2 evidências de telegram para a MESMA org
INSERT INTO public.telegram_evidence_uploads (
  organization_id, driver_id, chat_id, telegram_message_id,
  file_name, forensic_hash, storage_path
)
SELECT
  '00000000-0000-0000-0000-00000000aaaa'::UUID,
  '00000000-0000-0000-0000-000000000099'::UUID,
  100,
  g,
  'tel_' || g || '.jpg',
  repeat('0', 64),
  'org-aaaa/telegram/' || g || '.jpg'
FROM generate_series(1, 2) g;

-- Refresh manual (em dev — em prod o pg_cron faria)
REFRESH MATERIALIZED VIEW public.mv_evidence_volume;
```

**Verificação:**

```sql
SELECT total_historical, total_monthly
FROM public.mv_evidence_volume
WHERE organization_id = '00000000-0000-0000-0000-00000000aaaa'::UUID;
```

**Critério de aceitação:** `total_historical = 5` e `total_monthly = 5` (todas inseridas no mês corrente).

**Critério de falha:** Valor diferente de 5 em `total_historical` indica `UNION` (com dedup) em vez de `UNION ALL`, ou GROUP BY incorreto.

---

### CT-AG-02: Boundary de `total_monthly` em UTC (INV-6)

**Hipótese forense:** Evidências cuja `uploaded_at_utc` é anterior ao primeiro dia do mês corrente em UTC devem contar em `total_historical` mas não em `total_monthly`.

**Setup:**

```sql
-- Inserir evidência com data BACKDATED para o mês anterior
INSERT INTO public.justification_evidence_uploads (
  justification_id, organization_id, file_name, content_hash, storage_path,
  uploaded_at_utc
) VALUES (
  '00000000-0000-0000-0000-000000000002'::UUID,
  '00000000-0000-0000-0000-00000000bbbb'::UUID,
  'old.pdf',
  repeat('1', 64),
  'org-bbbb/just/old.pdf',
  (date_trunc('month', NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day') AT TIME ZONE 'UTC'
);

-- E uma do mês atual
INSERT INTO public.justification_evidence_uploads (
  justification_id, organization_id, file_name, content_hash, storage_path
) VALUES (
  '00000000-0000-0000-0000-000000000003'::UUID,
  '00000000-0000-0000-0000-00000000bbbb'::UUID,
  'new.pdf',
  repeat('2', 64),
  'org-bbbb/just/new.pdf'
);

REFRESH MATERIALIZED VIEW public.mv_evidence_volume;
```

**Verificação:**

```sql
SELECT total_historical, total_monthly
FROM public.mv_evidence_volume
WHERE organization_id = '00000000-0000-0000-0000-00000000bbbb'::UUID;
```

**Critério de aceitação:** `total_historical = 2`, `total_monthly = 1`. Confirma que `date_trunc('month', NOW() AT TIME ZONE 'UTC')` aplica boundary correto.

**Critério de falha:** `total_monthly = 2` indica que o filtro está usando timezone local (violação de INV-6).

---

### CT-AG-03: Org Sem Evidência Não Aparece na MV (compatível com Edge fallback)

**Hipótese forense:** O `GROUP BY` só emite linhas para orgs com pelo menos 1 evidência. A Edge Function trata `maybeSingle()` retornando `null` como `{ data: {} }`, e o `EvidenceVolumeView.fromJson` retorna zeros — verificável em `lib/application/super_admin/evidence_volume_view.dart:25-30`.

```sql
-- Org sem evidência
SELECT *
FROM public.mv_evidence_volume
WHERE organization_id = '00000000-0000-0000-0000-00000000cccc'::UUID;
```

**Critério de aceitação:** Zero linhas. O contrato com a Edge Function se mantém — a UI exibe `0 / 0` para orgs novas.

**Critério de falha:** Linha presente com contagens > 0 (impossível por design — alerta para bug de bind).

---

### CT-AG-04: Determinismo (INV-15) — Refresh Idempotente

**Hipótese forense:** Para o mesmo conjunto de linhas-fonte, dois `REFRESH` consecutivos produzem estado idêntico (modulo o filtro de mês corrente, que avança no tempo real).

```sql
-- Capturar snapshot
CREATE TEMP TABLE mv_snap_1 AS
SELECT * FROM public.mv_evidence_volume ORDER BY organization_id;

REFRESH MATERIALIZED VIEW public.mv_evidence_volume;

CREATE TEMP TABLE mv_snap_2 AS
SELECT * FROM public.mv_evidence_volume ORDER BY organization_id;

-- Diferença esperada: 0 linhas
SELECT * FROM mv_snap_1 EXCEPT SELECT * FROM mv_snap_2;
SELECT * FROM mv_snap_2 EXCEPT SELECT * FROM mv_snap_1;
```

**Critério de aceitação:** Ambos os `EXCEPT` retornam zero linhas. Confirma INV-15 (replay byte-idêntico).

**Critério de falha:** Qualquer diferença sem que linhas-fonte tenham mudado entre refreshes — indica não-determinismo (e.g. `ORDER BY` com chave não-única, uso de `random()` ou `clock_timestamp()`).

---

## Grupo 3 — Refresh CONCURRENTLY e Resiliência (INV-DB, INV-23)

### Objetivo

Confirmar que `REFRESH CONCURRENTLY` funciona (depende do UNIQUE INDEX), que não bloqueia SELECTs concorrentes, e que o guard de `pg_cron` permite que a migração rode em ambientes sem a extensão.

---

### CT-RF-01: REFRESH CONCURRENTLY Não Bloqueia Leituras

**Hipótese forense:** Com o UNIQUE INDEX em `organization_id`, `REFRESH MATERIALIZED VIEW CONCURRENTLY` pega apenas `ExclusiveLock` em um sketch temporário e troca o conteúdo atomicamente — não bloqueia SELECTs concorrentes.

**Sessão A (leitor):**

```sql
-- Loop de leituras durante o refresh da Sessão B
SELECT now(), count(*) FROM public.mv_evidence_volume;
```
(Executar repetidamente — não deve travar.)

**Sessão B (refresh):**

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_evidence_volume;
```

**Critério de aceitação:** Sessão A não trava em nenhum momento. `pg_stat_activity` da Sessão A nunca exibe `wait_event_type = 'Lock'` na MV durante o refresh.

**Critério de falha:** Sessão A bloqueia — indica que o `CONCURRENTLY` não está funcionando (falta de UNIQUE INDEX faria `REFRESH CONCURRENTLY` falhar com erro `cannot refresh materialized view concurrently`).

---

### CT-RF-02: Guard `pg_cron` Permite Execução em Dev Local (INV-23)

**Hipótese forense:** A migração não pode requerer `pg_cron` (extensão não disponível em `supabase start` local). O bloco `DO $$ IF EXISTS pg_namespace 'cron' ...` deve sair silenciosamente quando `cron` não existe.

```sql
-- Em supabase local — pg_cron ausente
SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron') AS cron_present;
-- → false em dev local; true em Cloud
```

**Critério de aceitação local:** A migração `20260706020000_mv_evidence_volume.sql` aplica-se em `supabase db reset` sem erro. MV existe e está populada (initial REFRESH executou).

**Critério de aceitação Cloud:**

```sql
-- Após apply em Cloud
SELECT jobname, schedule, command
FROM cron.job
WHERE jobname = 'refresh-mv-evidence-volume';
```
Esperado: uma linha com `schedule = '*/5 * * * *'` e `command` contendo `REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_evidence_volume`.

**Critério de falha:** Migração falha em dev local com `schema "cron" does not exist` — indica que o guard `IF EXISTS` foi removido por engano.

---

### CT-RF-03: Idempotência da Migração

**Hipótese forense:** Toda DDL usa `IF EXISTS` / `IF NOT EXISTS` / `OR REPLACE`. Re-executar a migração não deve produzir erro nem duplicar o job cron.

**Procedimento:** Executar manualmente o arquivo de migração duas vezes seguidas em ambiente local.

**Critério de aceitação:** Segunda execução completa sem erro. `cron.job` (em Cloud) ainda tem exatamente uma linha com `jobname = 'refresh-mv-evidence-volume'` (graças ao `cron.unschedule` no DO block).

**Critério de falha:** Erro `relation already exists` ou múltiplas linhas em `cron.job` para o mesmo `jobname`.

---

## Grupo 4 — Integração com Edge Function e Provider Dart

### Objetivo

Validar que após a migração o pipeline completo (Edge Function → repositório Dart → provider Riverpod) responde sem `PGRST205` e que o E2E `adverse_scenarios_test.dart` cenário 8.1 deixa de quebrar com `ErrorWidget`.

---

### CT-INT-01: Edge `get_evidence_volume` Responde 200

**Procedimento:**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/super-admin-proxy \
  -H "Authorization: Bearer $SUPABASE_USER_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "get_evidence_volume",
    "params": { "organization_id": "00000000-0000-0000-0000-00000000aaaa" }
  }'
```

**Critério de aceitação:** HTTP 200 com body `{"data": {"total_historical": <int>, "total_monthly": <int>}}` (ou `{"data": {}}` para org sem evidência). Log do Edge não exibe `PGRST205`.

**Critério de falha:** HTTP 500 com `PGRST205 — Could not find the table 'public.mv_evidence_volume'` — indica que migração não foi aplicada ou schema cache do PostgREST não foi refrescado (`bash scripts/refresh_schema_cache.sh`).

---

### CT-INT-02: E2E `adverse_scenarios_test.dart` 8.1 Passa

**Procedimento:**

```pwsh
flutter test integration_test/superadmin_adverse_scenarios_test.dart `
  --dart-define=SKIP_MFA_DEV=true `
  --plain-name "8.1 Consistência ao arquivar org sob race condition"
```

**Critério de aceitação:** Teste passa (cenário 8.1 verde). Provider `evidenceVolumeView` não lança, `TenantDetail` renderiza sem `ErrorWidget`, o fluxo de Arquivar completa.

**Critério de falha:** Teste continua falhando — diagnosticar com logs do Edge (`docker logs supabase_edge_runtime_veraprob`) para confirmar resolução do `PGRST205`. Se erro mudou, é outro layer (não escopo desta migração).

---

## Matriz de Rastreabilidade

| Caso de Teste | Invariante | Tipo | Automatizável | Prioridade |
|---|---|---|---|---|
| CT-ST-01 | INV-7 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-ST-02 | INV-DB | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-ST-03 | INV-1, INV-22 | Permission Audit | Sim (CI) | P0 - Bloqueante |
| CT-ST-04 | INV-22 | Red Team | Sim (CI) | P0 - Bloqueante |
| CT-AG-01 | INV-7, INV-15 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-AG-02 | INV-6 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-AG-03 | INV-1 | SQL Assertion | Sim (CI) | P1 |
| CT-AG-04 | INV-15 | Determinism | Sim (CI) | P0 - Bloqueante |
| CT-RF-01 | INV-DB | Concurrency | Manual | P1 |
| CT-RF-02 | INV-23 | Env Compat | Sim (CI local) | P0 - Bloqueante |
| CT-RF-03 | INV-DB | Idempotency | Manual | P1 |
| CT-INT-01 | INV-1 | Integration | Sim (CI) | P0 - Bloqueante |
| CT-INT-02 | n/a | E2E | Sim (CI) | P0 - Bloqueante |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 - Bloqueante** devem passar antes do merge. Falha em qualquer P0 é **VETO automático** pelo Reviewer Persona.

| Gate | Condição |
|---|---|
| **PASS** | CT-ST-01..04 verificam estrutura/permissões; CT-AG-01/02/04 confirmam agregação correta e determinística; CT-RF-02 confirma compat com dev local; CT-INT-01/02 confirmam pipeline end-to-end (Edge 200 + E2E 8.1 verde) |
| **VETO** | Qualquer P0 fora do esperado, especialmente CT-ST-03/04 (vazamento cross-tenant) ou CT-AG-02 (boundary de timezone errada) |
| **WARN** | CT-RF-01/03 — útil mas não bloqueia merge se justificado |

---

## Pós-Apply Checklist (Operador)

1. [ ] `supabase db reset` em local — migração aplica sem erro
2. [ ] `bash scripts/sync_db_types.sh` — `supabase/types.database.ts` regenerado e commitado (H-02)
3. [ ] `bash scripts/refresh_schema_cache.sh` — PostgREST vê a nova MV (H-09)
4. [ ] `flutter test test/integration/e2e/superadmin/adverse_scenarios_test.dart --plain-name "8.1"` — verde
5. [ ] Em Cloud: confirmar `SELECT * FROM cron.job WHERE jobname = 'refresh-mv-evidence-volume'` retorna uma linha

---

## Artefatos de Evidência (Forensic Chain of Custody)

1. **Output** de CT-ST-01: schema de colunas (3 linhas com tipos exatos)
2. **Output** de CT-ST-03: `role_table_grants` (apenas `service_role`)
3. **Output** de CT-AG-01/02: contagens esperadas vs. obtidas
4. **Output** de CT-AG-04: `EXCEPT` vazio em ambos os sentidos
5. **Log** do Edge Function durante CT-INT-01 (ausência de `PGRST205`)
6. **Output** de `flutter test` para CT-INT-02 (teste verde)
