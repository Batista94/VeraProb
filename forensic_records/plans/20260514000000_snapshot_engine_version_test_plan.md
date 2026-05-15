# Forensic Test Plan — Migration `20260514000000_snapshot_engine_version`

> **Classificação:** Engineering Study / Forensic Audit
> **Emitido por:** QA/Security Council Persona
> **Data de emissão:** 2026-05-14
> **Migração alvo:** `supabase/migrations/20260514000000_snapshot_engine_version.sql`
> **Tabela afetada:** `public.contractual_financial_snapshot`
> **Coluna introduzida:** `engine_version TEXT NOT NULL`
> **Invariantes cobertos:** INV-3 (Ledger Append-Only), INV-5 (Basis Points Inteiros), INV-7 (Tipos Estritos), INV-15 (Replay Determinístico), INV-21 (Snapshot ID do Veredicto), INV-DB (Zero-Downtime Pattern)
> **Migração corretiva associada:** `supabase/migrations/20260706010000_snapshot_forensic_integrity_hardening.sql` (ver Grupo 6)

---

## Contexto da Investigação

Esta migração sela a **versão do motor de cálculo** em cada snapshot financeiro contratual, garantindo que um auditor forense possa reproduzir deterministicamente o veredicto de qualquer dia histórico com o motor exato que o gerou (INV-21). A coluna não possui `DEFAULT` no banco — a aplicação é a única fonte autorizada da versão, injetada via `--dart-define=ENGINE_VERSION=...` em build time.

Linhas pré-existentes (sem versão) são promovidas para `legacy-unversioned` pelo backfill idempotente do Step 2.

---

## Pré-condições de Ambiente

| Item | Valor esperado |
|---|---|
| PostgreSQL | ≥ 14 (PG 14+ exigido para `SET NOT NULL` metadata-only após constraint validation) |
| Migração aplicada | `\dt contractual_financial_snapshot` exibe coluna `engine_version` |
| Ambiente de teste | Supabase local (`supabase start`) ou staging isolado |
| Acesso ao `pg_stat_activity` | Requerido para testes de lock (Grupo 2) |

---

## Grupo 1 — Validação de Integridade do Backfill

### Objetivo

Garantir que nenhuma linha pré-migração ficou com `engine_version IS NULL`, o que quebraria a invariante INV-3 (ledger como registro imutável e completo) e impossibilitaria replay forense.

---

### CT-EV-01: Ausência Total de Nulos Pós-Migração

**Hipótese forense:** O backfill do Step 2 cobriu 100% das linhas existentes.

**Script de verificação (executar no console Supabase ou `psql`):**

```sql
-- RESULTADO ESPERADO: 0 (zero linhas nulas)
SELECT COUNT(*) AS null_engine_version_count
FROM public.contractual_financial_snapshot
WHERE engine_version IS NULL;
```

**Critério de aceitação:** `null_engine_version_count = 0`.
**Critério de falha:** Qualquer valor > 0 indica que o backfill não foi aplicado ou a migração rodou parcialmente.

---

### CT-EV-02: Distribuição de Valores de Versão

**Hipótese forense:** Linhas legadas têm `legacy-unversioned`; linhas novas têm versões semânticas (`v1.0.0`, `v1.1.0`, etc.).

```sql
-- RESULTADO ESPERADO: apenas 'legacy-unversioned' para linhas antigas
-- + versões semânticas para linhas pós-migração
SELECT
  engine_version,
  COUNT(*) AS row_count,
  MIN(closed_at_utc) AS earliest,
  MAX(closed_at_utc) AS latest
FROM public.contractual_financial_snapshot
GROUP BY engine_version
ORDER BY latest DESC;
```

**Critério de aceitação:**
- Coluna `legacy-unversioned` existe apenas para snapshots com `closed_at_utc` anterior à data da migração (`2026-05-14`).
- Nenhuma linha com `closed_at_utc >= '2026-05-14'` deve ter `engine_version = 'legacy-unversioned'` (isso indicaria que a aplicação não está injetando a versão corretamente).

---

### CT-EV-03: Idempotência do Backfill

**Hipótese forense:** Re-executar a migração não altera nenhuma linha nova (o `WHERE engine_version IS NULL` é o guard).

```sql
-- Captura snapshot antes
SELECT COUNT(*) AS versioned_count
FROM public.contractual_financial_snapshot
WHERE engine_version <> 'legacy-unversioned';

-- Re-executa apenas o Step 2 isolado
UPDATE public.contractual_financial_snapshot
  SET engine_version = 'legacy-unversioned'
  WHERE engine_version IS NULL;

-- Valida que a contagem de linhas versionadas NÃO mudou
SELECT COUNT(*) AS versioned_count_after
FROM public.contractual_financial_snapshot
WHERE engine_version <> 'legacy-unversioned';
```

**Critério de aceitação:** `versioned_count = versioned_count_after`. Zero linhas alteradas na segunda execução.

---

### CT-EV-04: Integridade da Restrição NOT NULL no Catálogo

**Hipótese forense:** O Step 3c elevou a restrição para o catálogo (metadata-only no PG 14+), sem scan de tabela.

```sql
-- RESULTADO ESPERADO: is_nullable = 'NO'
SELECT
  column_name,
  is_nullable,
  data_type,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'contractual_financial_snapshot'
  AND column_name = 'engine_version';
```

**Critério de aceitação:**
- `is_nullable = 'NO'`
- `column_default IS NULL` (sem default — a aplicação é a fonte)
- `data_type = 'text'`

---

### CT-EV-05: Comentário de Auditoria no Catálogo

```sql
-- Verifica se o COMMENT do Step 4 foi persistido
SELECT obj_description(
  (
    SELECT attrelid || ',' || attnum
    FROM pg_attribute
    JOIN pg_class ON pg_class.oid = pg_attribute.attrelid
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_namespace.nspname = 'public'
      AND pg_class.relname = 'contractual_financial_snapshot'
      AND pg_attribute.attname = 'engine_version'
  )::text::oid,
  'pg_attribute'
) AS column_comment;
```

> **Alternativa simplificada (psql):**
> ```
> \d+ contractual_financial_snapshot
> ```
> Localizar a coluna `engine_version` e confirmar que o comentário começa com `Engine version that produced this snapshot`.

**Critério de aceitação:** Comentário presente e legível por auditores externos via `\d+`.

---

## Grupo 2 — Validação de Zero-Downtime (INV-DB)

### Objetivo

Confirmar que o padrão de 4 passos (`NOT VALID → VALIDATE → SET NOT NULL → DROP CONSTRAINT`) não adquiriu `AccessExclusiveLock` na tabela durante a execução. Um `AccessExclusiveLock` bloqueia todas as leituras e escritas — inaceitável em produção simulada.

---

### CT-ZD-01: Monitoramento de Locks Durante Simulação da Migração

**Procedimento:** Executar em duas sessões simultâneas no Supabase local.

**Sessão A — Monitor de locks (abrir antes da migração):**

```sql
-- Monitorar a cada 500ms enquanto a Sessão B roda
SELECT
  pid,
  query_start,
  state,
  wait_event_type,
  wait_event,
  left(query, 80) AS query_snippet
FROM pg_stat_activity
WHERE state <> 'idle'
  AND query NOT ILIKE '%pg_stat_activity%'
ORDER BY query_start;
```

**Sessão B — Executar migração completa:**

```sql
-- Rodar toda a sequência de Steps 3a → 3d
ALTER TABLE public.contractual_financial_snapshot
  ADD CONSTRAINT chk_engine_version_not_null
  CHECK (engine_version IS NOT NULL)
  NOT VALID;

ALTER TABLE public.contractual_financial_snapshot
  VALIDATE CONSTRAINT chk_engine_version_not_null;

ALTER TABLE public.contractual_financial_snapshot
  ALTER COLUMN engine_version SET NOT NULL;

ALTER TABLE public.contractual_financial_snapshot
  DROP CONSTRAINT chk_engine_version_not_null;
```

**Critério de aceitação:** Durante execução, `pg_stat_activity` na Sessão A **não deve exibir** `wait_event = 'relation'` com `wait_event_type = 'Lock'` para a tabela `contractual_financial_snapshot`. Reads paralelas devem completar sem bloqueio.

---

### CT-ZD-02: Auditoria de Tipo de Lock por Step

**Hipótese forense:** Mapeamento esperado de lock por etapa:

| Step | Operação | Lock Esperado | Bloqueia Reads? |
|------|----------|---------------|-----------------|
| 3a | `ADD CONSTRAINT ... NOT VALID` | `ShareRowExclusiveLock` | Não |
| 3b | `VALIDATE CONSTRAINT` | `ShareUpdateExclusiveLock` | Não |
| 3c | `ALTER COLUMN SET NOT NULL` (após validation) | `ShareUpdateExclusiveLock` (metadata-only PG14+) | Não |
| 3d | `DROP CONSTRAINT` | `AccessExclusiveLock` (breve, ~ms) | Sim (ms apenas) |

```sql
-- Consultar pg_locks durante execução da migração
SELECT
  l.pid,
  l.mode,
  l.granted,
  c.relname AS table_name
FROM pg_locks l
JOIN pg_class c ON c.oid = l.relation
WHERE c.relname = 'contractual_financial_snapshot'
  AND l.locktype = 'relation'
ORDER BY l.mode;
```

**Critério de aceitação:** Nenhum `mode = 'AccessExclusiveLock'` com `granted = true` durante os Steps 3a, 3b, 3c. O Step 3d pode adquiri-lo brevemente (< 10ms em produção simulada).

---

### CT-ZD-03: Verificação de Transações Simultâneas

**Procedimento:** Simular carga de leitura durante migração.

```sql
-- Sessão C — workload simulado (rodar em loop enquanto migração executa)
DO $$
DECLARE i INT := 0;
BEGIN
  WHILE i < 1000 LOOP
    PERFORM COUNT(*) FROM public.contractual_financial_snapshot;
    i := i + 1;
  END LOOP;
END $$;
```

**Critério de aceitação:** O loop da Sessão C completa sem erro de deadlock ou timeout. Tempo total do loop não deve exceder 2x o tempo basal (sem migração paralela).

---

## Grupo 3 — Teste de Regressão de Inserção (Camada Dart/Flutter)

### Objetivo

Garantir que a remoção do `DEFAULT` do banco e a promoção para `NOT NULL` forçam a camada de aplicação a sempre fornecer `engine_version`. Qualquer INSERT sem este campo deve falhar na camada de domínio (antes de chegar ao banco).

---

### CT-IR-01: DomainException para engineVersion Vazio

**Localização:** `lib/domain/sla_audit/contractual_financial_daily_snapshot.dart:108`

**Comportamento esperado:** `ContractualFinancialDailySnapshot.create(engineVersion: '')` lança `DomainException`.

**Script de teste (adicionar em `test/domain/sla_audit/`):**

```dart
test('CT-IR-01: create() throws DomainException when engineVersion is empty', () {
  expect(
    () => ContractualFinancialDailySnapshot.create(
      organizationId: 'org-test',
      contractId: null,
      operationalDateUtc: DateTime.utc(2026, 5, 14),
      operationalTimezone: 'America/Sao_Paulo',
      closedAtUtc: DateTime.utc(2026, 5, 14, 22, 0),
      totalContractedRevenue: Money(100000),
      protectedRevenue: Money(95000),
      revenueAtRisk: Money(5000),
      lostRevenue: Money(0),
      totalObligations: 10,
      executedCount: 9,
      noShowCount: 1,
      evidenceGapCount: 0,
      lastLedgerEntryId: null,
      engineVersion: '', // DEVE REJEITAR
    ),
    throwsA(isA<DomainException>()),
  );
});
```

**Critério de aceitação:** Teste passa. `DomainException` disparada antes de qualquer chamada ao Supabase.

---

### CT-IR-02: Rejeição no Banco para INSERT Sem engine_version

**Hipótese forense:** Se uma regressão contornar a validação de domínio, o banco deve ser a última linha de defesa.

```sql
-- DEVE FALHAR com: null value in column "engine_version" violates not-null constraint
INSERT INTO public.contractual_financial_snapshot (
  id,
  organization_id,
  operational_date_utc,
  operational_timezone,
  closed_at_utc,
  total_contracted_revenue_cents,
  protected_revenue_cents,
  revenue_at_risk_cents,
  lost_revenue_cents,
  risk_percentage_bps,
  loss_percentage_bps,
  total_obligations,
  executed_count,
  no_show_count,
  evidence_gap_count
) VALUES (
  gen_random_uuid(),
  'org-regression-test',
  '2026-05-14 00:00:00Z',
  'America/Sao_Paulo',
  '2026-05-14 22:00:00Z',
  100000, 95000, 5000, 0,
  500, 0,
  10, 9, 1, 0
);
-- engine_version omitido propositalmente
```

**Critério de aceitação:** PostgreSQL retorna `ERROR 23502: null value in column "engine_version"`. Nenhum registro inserido.

---

### CT-IR-03: INSERT Válido com engineVersion Semântica

```sql
-- DEVE SUCEDER
INSERT INTO public.contractual_financial_snapshot (
  id,
  organization_id,
  operational_date_utc,
  operational_timezone,
  closed_at_utc,
  total_contracted_revenue_cents,
  protected_revenue_cents,
  revenue_at_risk_cents,
  lost_revenue_cents,
  risk_percentage_bps,
  loss_percentage_bps,
  total_obligations,
  executed_count,
  no_show_count,
  evidence_gap_count,
  engine_version
) VALUES (
  gen_random_uuid(),
  'org-regression-test',
  '2026-05-14 00:00:00Z',
  'America/Sao_Paulo',
  '2026-05-14 22:00:00Z',
  100000, 95000, 5000, 0,
  500, 0,
  10, 9, 1, 0,
  'v1.0.0' -- versão semântica fornecida pela app
);

-- Verificar inserção
SELECT id, engine_version, closed_at_utc
FROM public.contractual_financial_snapshot
WHERE organization_id = 'org-regression-test'
ORDER BY closed_at_utc DESC
LIMIT 1;
```

**Critério de aceitação:** Linha inserida com `engine_version = 'v1.0.0'`. Cleanup obrigatório após o teste:

```sql
DELETE FROM public.contractual_financial_snapshot
WHERE organization_id = 'org-regression-test';
```

> **Nota INV-3:** Após a migração `20260706010000`, o trigger `trg_snapshot_no_delete` bloqueia `DELETE` em qualquer ambiente e role (ver CT-FH-09). O cleanup deste caso passa a exigir `supabase db reset` ou execução antes da migração de hardening. Em produção, `DELETE` é proibido; somente cadeia de reprocessamento.

---

### CT-IR-04: Reconstitution Sem Fallback em Dados Pós-Migração

**Localização:** `lib/infrastructure/sla_audit/postgres_contractual_financial_snapshot_repository.dart:203`

**Hipótese forense:** O fallback `?? 'legacy-unversioned'` no `_mapRow` é um guard defensivo para ambientes de teste sem migrações. Em produção, nenhuma linha deve precisar dele após esta migração.

```sql
-- Confirmar que NENHUMA linha retornaria NULL do banco
-- (o fallback nunca deve ser ativado em produção)
SELECT COUNT(*) AS rows_that_would_trigger_fallback
FROM public.contractual_financial_snapshot
WHERE engine_version IS NULL;
```

**Critério de aceitação:** `rows_that_would_trigger_fallback = 0`. O fallback no Dart é dead code em produção — documentar na PR que ele pode ser removido em um ciclo futuro após estabilização.

---

## Grupo 4 — Audit Trail (Rastreabilidade Forense INV-21)

### Objetivo

Confirmar que snapshots gerados pós-migração incluem `engine_version` como parte permanente e visível do registro de auditoria, garantindo que qualquer contestação financeira seja resolvível com a versão exata do motor utilizado.

---

### CT-AT-01: engine_version Presente em Snapshots Pós-Migração

```sql
-- RESULTADO ESPERADO: todas as linhas pós-migração têm engine_version não-nulo e não-legado
SELECT
  id,
  organization_id,
  engine_version,
  closed_at_utc,
  CASE
    WHEN engine_version = 'legacy-unversioned' THEN 'PRE-MIGRATION (legado aceito)'
    WHEN engine_version ~ '^v[0-9]+\.[0-9]+\.[0-9]+' THEN 'POST-MIGRATION (ok)'
    ELSE 'FORMATO INESPERADO (investigar)'
  END AS version_status
FROM public.contractual_financial_snapshot
ORDER BY closed_at_utc DESC
LIMIT 50;
```

**Critério de aceitação:** Nenhuma linha com `version_status = 'FORMATO INESPERADO'`. Linhas `>= 2026-05-14` devem ter `POST-MIGRATION (ok)`.

---

### CT-AT-02: Rastreabilidade de Reprocessamento com engine_version

**Hipótese forense:** Um snapshot de reprocessamento deve registrar a versão do motor que gerou a **correção**, não a versão original.

```sql
-- Verificar cadeia de reprocessamento
SELECT
  s.id,
  s.engine_version AS current_version,
  prev.engine_version AS previous_version,
  s.reprocessing_reason,
  s.closed_at_utc
FROM public.contractual_financial_snapshot s
LEFT JOIN public.contractual_financial_snapshot prev
  ON prev.id = s.previous_snapshot_id
WHERE s.previous_snapshot_id IS NOT NULL
ORDER BY s.closed_at_utc DESC;
```

**Critério de aceitação:** Toda linha com `previous_snapshot_id NOT NULL` deve ter `current_version` diferente de NULL. A diferença entre `current_version` e `previous_version` pode ser usada para identificar qual versão do motor corrigiu o erro original.

---

### CT-AT-03: Consulta de Auditoria por engine_version (Filtro Forense)

```sql
-- Listar todos os snapshots produzidos por uma versão específica
-- Usado em investigações: "quais contratos foram calculados pela versão v1.0.0?"
SELECT
  organization_id,
  contract_id,
  operational_date_utc,
  engine_version,
  lost_revenue_cents,
  closed_at_utc
FROM public.contractual_financial_snapshot
WHERE engine_version = 'v1.0.0'
  AND organization_id = :org_id  -- filtro de tenant obrigatório (INV-1)
ORDER BY operational_date_utc DESC;
```

**Critério de aceitação:** Query retorna apenas linhas do `organization_id` especificado (RLS em vigor — INV-1, INV-2). Zero cross-tenant leakage.

---

### CT-AT-04: Reprodutibilidade Determinística (INV-15 + INV-21)

**Hipótese forense:** Dado um `snapshot.id`, o auditor deve conseguir identificar:
1. A versão do motor (`engine_version`)
2. O último evento do ledger considerado (`last_ledger_entry_uuid`)
3. O timestamp exato de fechamento (`closed_at_utc`)

Esses três elementos juntos garantem **byte-identical replay** (INV-15).

```sql
-- Ficha de auditoria completa de um snapshot
SELECT
  id AS snapshot_id,
  engine_version,
  last_ledger_entry_uuid,
  closed_at_utc,
  operational_date_utc,
  organization_id,
  contract_id,
  previous_snapshot_id,
  reprocessing_reason
FROM public.contractual_financial_snapshot
WHERE id = :snapshot_id;
```

**Critério de aceitação:** Todos os quatro campos de rastreabilidade (`engine_version`, `last_ledger_entry_uuid`, `closed_at_utc`, `operational_date_utc`) são NOT NULL para qualquer snapshot pós-migração.

---

## Grupo 5 — Casos de Borda e Segurança

### CT-SE-01: Tentativa de UPDATE em engine_version (INV-3)

**Hipótese forense:** O ledger é append-only. Nenhuma linha deve ser atualizável após criação.

```sql
-- DEVE FALHAR se RLS e políticas de ledger estiverem corretas
-- (ou ser bloqueado pela camada de aplicação que não expõe UPDATE)
UPDATE public.contractual_financial_snapshot
SET engine_version = 'tampered-version'
WHERE id = (SELECT id FROM public.contractual_financial_snapshot LIMIT 1);
```

**Critério de aceitação:** Se RLS bloquear: `ERROR 42501: new row violates row-level security policy`. Se não houver RLS para UPDATE: documentar como gap de segurança para próximo ciclo de auditoria.

---

### CT-SE-02: Isolamento de Tenant em Leitura por engine_version

```sql
-- Simular consulta de Tenant A tentando ler dados do Tenant B via filtro de versão
-- (RLS deve garantir que apenas dados do próprio tenant retornem — INV-22)
SET request.jwt.claims = '{"organization_id": "tenant-a-id"}';

SELECT COUNT(*) AS cross_tenant_count
FROM public.contractual_financial_snapshot
WHERE engine_version = 'v1.0.0'
  AND organization_id = 'tenant-b-id';  -- outro tenant
```

**Critério de aceitação:** `cross_tenant_count = 0` mesmo com JWT de Tenant A. RLS (`auth.jwt() ->> 'organization_id'`) deve bloquear o acesso (INV-2, INV-22).

---

## Grupo 6 — Hardening Forense Pós-Auditoria (Migração `20260706010000`)

### Objetivo

A execução do Grupo 1–5 revelou três defeitos estruturais na tabela `contractual_financial_snapshot` que não pertencem à migração `20260514000000`, mas comprometem a mesma cadeia de custódia. A migração corretiva `20260706010000_snapshot_forensic_integrity_hardening.sql` os endereça. Este grupo valida essa correção.

| Bug | Defeito | Invariante violado |
|---|---|---|
| BUG-1 | `risk_percentage` / `loss_percentage` armazenados como `FLOAT8` e com nome enganoso (uma "percentage" valendo 500 = 5%, não 500%) | INV-5 (basis points são inteiros), INV-15 (replay byte-idêntico) |
| BUG-2 | `last_ledger_entry_id` (BIGINT) e `last_ledger_entry_uuid` (TEXT) podem coexistir — referência ambígua | INV-15, INV-21 (fronteira causal determinística) |
| BUG-3 | Tabela imutável sem trigger de bloqueio; `REVOKE` não detém `service_role`; coluna `updated_at` vestigial | INV-3 (append-only) |

---

### CT-FH-01: BUG-1 — Colunas de Percentual Promovidas para INTEGER e Renomeadas

**Hipótese forense:** O padrão add/backfill/drop substituiu os `FLOAT8` `risk_percentage` / `loss_percentage` pelos `INTEGER` `risk_percentage_bps` / `loss_percentage_bps` — alinhados aos campos de domínio `riskPercentageBps` / `lossPercentageBps`.

```sql
-- RESULTADO ESPERADO: risk_percentage_bps e loss_percentage_bps com
-- data_type = 'integer', is_nullable = 'NO'; as colunas float antigas não existem.
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'contractual_financial_snapshot'
  AND column_name IN ('risk_percentage', 'loss_percentage',
                      'risk_percentage_bps', 'loss_percentage_bps')
ORDER BY column_name;
```

**Critério de aceitação:** Apenas `risk_percentage_bps` e `loss_percentage_bps` retornam, ambas `integer` / `NO`. Nenhuma coluna `risk_percentage` / `loss_percentage` (float) residual deve permanecer.

---

### CT-FH-02: BUG-1 — Preservação de Valor no Backfill

**Hipótese forense:** O backfill `round(<float>)::int` preservou o basis point mais próximo de cada linha legada — nenhuma perda silenciosa por truncamento.

```sql
-- Executar ANTES da migração (capturar baseline — colunas float ainda existem):
SELECT id, risk_percentage AS risk_float, loss_percentage AS loss_float
FROM public.contractual_financial_snapshot
ORDER BY id;

-- Executar APÓS a migração e comparar (colunas int renomeadas):
SELECT id, risk_percentage_bps AS risk_int, loss_percentage_bps AS loss_int
FROM public.contractual_financial_snapshot
ORDER BY id;
```

**Critério de aceitação:** Para cada `id`, `risk_int = round(risk_float)` e `loss_int = round(loss_float)`. Em ambiente limpo (tabela vazia) o caso é trivialmente satisfeito — registrar como N/A com evidência da contagem zero.

---

### CT-FH-03: BUG-1 — Documentação de Catálogo (COMMENT)

```sql
SELECT a.attname AS column_name, col_description(a.attrelid, a.attnum) AS column_comment
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'contractual_financial_snapshot'
  AND a.attname IN ('risk_percentage_bps', 'loss_percentage_bps');
```

**Critério de aceitação:** Ambos os comentários presentes e contêm a string `INTEGER basis points`.

---

### CT-FH-04: BUG-2 — Constraint de Exclusividade Mútua Existe e Está Válida

```sql
SELECT conname, convalidated
FROM pg_constraint
WHERE conname = 'chk_ledger_entry_ref_exclusive';
```

**Critério de aceitação:** Uma linha retornada com `convalidated = true`.

---

### CT-FH-05: BUG-2 — Rejeição de Referência Ambígua

**Hipótese forense:** O banco recusa qualquer linha que popule ambas as colunas de ledger.

```sql
-- DEVE FALHAR com: new row for relation violates check constraint "chk_ledger_entry_ref_exclusive"
INSERT INTO public.contractual_financial_snapshot (
  id, organization_id, contract_id,
  operational_date_utc, operational_timezone, closed_at_utc,
  total_contracted_revenue_cents, protected_revenue_cents,
  revenue_at_risk_cents, lost_revenue_cents,
  risk_percentage_bps, loss_percentage_bps,
  total_obligations, executed_count, no_show_count, evidence_gap_count,
  last_ledger_entry_id, last_ledger_entry_uuid, engine_version
) VALUES (
  gen_random_uuid(), (SELECT id FROM public.organizations LIMIT 1), 'org-fh-test',
  '2026-07-06 00:00:00Z', 'America/Sao_Paulo', '2026-07-06 22:00:00Z',
  100000, 95000, 5000, 0,
  500, 0,
  10, 9, 1, 0,
  42, '00000000-0000-0000-0000-000000000001', 'v1.0.0'  -- AMBOS preenchidos
);
```

**Critério de aceitação:** `ERROR 23514: ... violates check constraint "chk_ledger_entry_ref_exclusive"`. Nenhum registro inserido.

---

### CT-FH-06: BUG-2 — COMMENT de Desambiguação nas Colunas de Ledger

```sql
SELECT a.attname AS column_name, col_description(a.attrelid, a.attnum) AS column_comment
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'contractual_financial_snapshot'
  AND a.attname IN ('last_ledger_entry_id', 'last_ledger_entry_uuid');
```

**Critério de aceitação:** `last_ledger_entry_id` marcado como `LEGACY`; `last_ledger_entry_uuid` marcado como `CANONICAL`.

---

### CT-FH-07: BUG-3 — Coluna `updated_at` Removida

```sql
-- RESULTADO ESPERADO: 0 linhas (coluna não existe mais)
SELECT COUNT(*) AS updated_at_still_present
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'contractual_financial_snapshot'
  AND column_name = 'updated_at';
```

**Critério de aceitação:** `updated_at_still_present = 0`.

---

### CT-FH-08: BUG-3 — Triggers de Imutabilidade Instalados

```sql
SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.contractual_financial_snapshot'::regclass
  AND tgname IN ('trg_snapshot_no_update', 'trg_snapshot_no_delete')
ORDER BY tgname;
```

**Critério de aceitação:** Duas linhas retornadas, ambas com `tgenabled = 'O'` (enabled).

---

### CT-FH-09: BUG-3 — UPDATE e DELETE Bloqueados no Nível Postgres

**Hipótese forense:** O trigger dispara antes de qualquer operação, independentemente do role — fechando o gap deixado pelo `REVOKE` (que não detém `service_role`).

```sql
-- DEVE FALHAR: 'contractual_financial_snapshot is immutable (INV-3). Operation: UPDATE'
UPDATE public.contractual_financial_snapshot
SET risk_percentage_bps = 9999
WHERE id = (SELECT id FROM public.contractual_financial_snapshot LIMIT 1);

-- DEVE FALHAR: 'contractual_financial_snapshot is immutable (INV-3). Operation: DELETE'
DELETE FROM public.contractual_financial_snapshot
WHERE id = (SELECT id FROM public.contractual_financial_snapshot LIMIT 1);
```

**Critério de aceitação:** Ambas falham com `ERRCODE = restrict_violation` e a mensagem `is immutable (INV-3)`. Substitui o resultado condicional de CT-SE-01 — a imutabilidade agora é garantida no banco, não apenas por disciplina de aplicação.

---

### CT-FH-10: Idempotência da Migração Corretiva

**Hipótese forense:** Re-executar `20260706010000` é um no-op — o bloco BUG-1 é guardado por `data_type = 'double precision'`; BUG-2/BUG-3 usam guards `IF [NOT] EXISTS`.

**Procedimento:** Aplicar a migração duas vezes (`supabase migration up` seguido de re-execução manual do arquivo). Após a segunda execução, repetir CT-FH-01, CT-FH-04, CT-FH-07, CT-FH-08.

**Critério de aceitação:** Resultados idênticos à primeira execução. Nenhum erro de "column already exists", "constraint already exists" ou "trigger already exists".

---

## Matriz de Rastreabilidade

| Caso de Teste | Invariante | Tipo | Automatable? | Prioridade |
|---|---|---|---|---|
| CT-EV-01 | INV-3, INV-DB | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-EV-02 | INV-21 | SQL Assertion | Sim (CI) | P0 - Bloqueante |
| CT-EV-03 | INV-DB | SQL Assertion | Sim (CI) | P1 |
| CT-EV-04 | INV-DB | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-EV-05 | INV-21 | Schema Check | Sim | P2 |
| CT-ZD-01 | INV-DB | Observabilidade | Manual (Prod-sim) | P0 - Bloqueante |
| CT-ZD-02 | INV-DB | Lock Audit | Manual | P1 |
| CT-ZD-03 | INV-DB | Load Simulation | Semi-automático | P1 |
| CT-IR-01 | INV-7, INV-21 | Dart Unit Test | Sim (CI) | P0 - Bloqueante |
| CT-IR-02 | INV-3 | SQL Constraint | Sim (CI) | P0 - Bloqueante |
| CT-IR-03 | INV-21 | Integration | Sim | P1 |
| CT-IR-04 | INV-21 | SQL + Code Review | Manual | P2 |
| CT-AT-01 | INV-21 | SQL Assertion | Sim (pós-deploy) | P1 |
| CT-AT-02 | INV-15, INV-21 | SQL Assertion | Semi-automático | P1 |
| CT-AT-03 | INV-1 | SQL + RLS | Sim (CI) | P0 - Bloqueante |
| CT-AT-04 | INV-15 | SQL Assertion | Sim | P1 |
| CT-SE-01 | INV-3 | RLS / Sec Test | Sim (CI) | P1 |
| CT-SE-02 | INV-22 | Red Team / RLS | Sim (CI) | P0 - Bloqueante |
| CT-FH-01 | INV-5, INV-15 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-FH-02 | INV-15 | SQL Assertion | Semi-automático | P1 |
| CT-FH-03 | INV-5 | Schema Check | Sim | P2 |
| CT-FH-04 | INV-15, INV-21 | Schema Check | Sim (CI) | P1 |
| CT-FH-05 | INV-15, INV-21 | SQL Constraint | Sim (CI) | P0 - Bloqueante |
| CT-FH-06 | INV-21 | Schema Check | Sim | P2 |
| CT-FH-07 | INV-3 | Schema Check | Sim (CI) | P1 |
| CT-FH-08 | INV-3 | Schema Check | Sim (CI) | P0 - Bloqueante |
| CT-FH-09 | INV-3 | Sec Test | Sim (CI) | P0 - Bloqueante |
| CT-FH-10 | INV-DB | Idempotency | Manual | P1 |

---

## Critério de Go/No-Go para Merge em Main

> Todos os casos **P0 - Bloqueante** devem passar antes do merge. Falha em qualquer P0 é **VETO automático** pelo Reviewer Persona.

| Gate | Condição |
|---|---|
| **PASS** | CT-EV-01 = 0 nulos; CT-EV-04 `is_nullable = NO`; CT-IR-01 DomainException lançada; CT-IR-02 INSERT rejeitado; CT-AT-03 zero cross-tenant; CT-FH-01 colunas `integer`; CT-FH-05 referência ambígua rejeitada; CT-FH-08 triggers instalados; CT-FH-09 UPDATE/DELETE bloqueados |
| **VETO** | Qualquer P0 com resultado diferente do esperado |
| **WARN** | CT-IR-04 fallback ativo (> 0 linhas NULL) — escalar para análise de dados |

---

## Artefatos de Evidência (Forensic Chain of Custody)

Ao concluir a execução, armazenar os seguintes artefatos no storage forense do ambiente:

1. **Screenshot** do resultado de CT-EV-01 (count = 0)
2. **Output** de `\d+ contractual_financial_snapshot` mostrando `NOT NULL` e sem default
3. **Log** de `pg_stat_activity` durante CT-ZD-01 (ausência de AccessExclusiveLock)
4. **Output** do teste Dart CT-IR-01 (stack trace da DomainException)

Estes artefatos constituem a **prova documental** de que a migração foi validada segundo os padrões de governança VeraProb e podem ser referenciados em auditorias contratuais futuras.
