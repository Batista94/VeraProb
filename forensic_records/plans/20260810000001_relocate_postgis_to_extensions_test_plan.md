# Plano de Testes — 20260810000001_relocate_postgis_to_extensions

**Migração:** `supabase/migrations/20260810000001_relocate_postgis_to_extensions.sql`
**Invariantes:** INV-1, INV-2, INV-3, INV-6, INV-13, INV-14 (catálogo de extensão fora do schema da API), INV-15, INV-22, INV-26.
**Risco:** Alto — corrige a RAIZ do advisor `rls_disabled_in_public`. A relocação física da extensão NÃO é executável pelo papel `postgres` (não-superuser; PostGIS é extensão não-trusted → `CREATE EXTENSION` exige superuser). No **plano FREE** ela é feita **self-serve** pelo Dashboard Supabase → Database → Extensions (que roda como papel privilegiado da plataforma em todos os tiers — sem ticket/sem upgrade). Esta migração é o lado-aplicação, aplicada na MESMA janela imediatamente após o re-enable.
**pgTAP:** `supabase/tests/20260810000001_relocate_postgis_to_extensions_test.sql` (7 testes — apenas o que é verificável pré-relocação).

---

## Raiz vs. Controle Interim

| Camada | Artefato | Tier | Estado |
|--------|----------|------|--------|
| Controle INTERIM | `20260810000000` guard trigger | `postgres` | **APLICADO** (fecha o vetor de escrita anônima já) |
| Lado-aplicação da raiz | `20260810000001` (este) | `postgres` | Staged — idempotente, seguro mesmo com PostGIS ainda em `public` |
| Relocação física | disable→re-enable PostGIS em `extensions` | Dashboard (papel privilegiado da plataforma) | Self-serve no plano FREE (ver Runbook abaixo) |

`20260704000001_autonomous_closer.sql:27` instalou PostGIS em `public` (`CREATE EXTENSION … SCHEMA public`), colocando o catálogo (`spatial_ref_sys`, `geometry_columns`, `geography_columns`) dentro do schema exposto pela PostgREST/Data API (INV-14). Mover para `extensions` remove a tabela da Data API → advisor limpa, `anon` perde alcance.

**Dependência PostGIS é estreita:** nenhuma tabela usa colunas `geometry`/`geography` (todo lat/lng = `DOUBLE PRECISION`). Superfície = 2 RPCs (`check_and_close_execution_autonomously`, `process_gps_for_execution_transitions`) via casts `ST_MakePoint(...)::geography` + 1 índice GIST `idx_operational_zones_geog`. → **relocação = zero perda de dados.**

A única mudança comportamental desta migração: `SET search_path = public` → `public, extensions` em ambos os RPCs, para que `ST_*` não-qualificado resolva pós-relocação. Corpos byte-idênticos a `20260704000003_backdating_support.sql`. Call sites permanecem não-qualificados (padrão `uuid-ossp`/`pgcrypto` de `20200101000000`).

---

## Runbook de Relocação (Self-Serve — plano FREE, Dashboard Supabase)

> **DESTRUTIVO (DROP EXTENSION via toggle) + janela de manutenção.** Executado pelo dono do projeto no Dashboard — **sem ticket, sem upgrade**. Durante o gap (PostGIS em `extensions` mas RPCs ainda `public`-only) todo ping GPS de `ingest-sascar`/`ingest-omnitracs` falharia. **Pausar ingest ou manter a janela em segundos.**
>
> **Pré-condição a confirmar:** o diálogo *Enable extension* do PostGIS deve expor o seletor **Schema** (default `extensions`). Se a sua instância forçar `public`, a relocação fica bloqueada → adotar a **Postura B (residual aceito)** abaixo; o guard interim permanece como controle durável.

**Fatos forenses (verificados na DB live):**
- Advisor: `rls_disabled_in_public` em `public.spatial_ref_sys`.
- Owner = `supabase_admin`; `postgres` não-superuser/não-owner/não-grantor (`rolsuper=false`, `pg_has_role(postgres,supabase_admin,MEMBER)=false`) → `postgres` NÃO consegue `DROP`/`CREATE EXTENSION postgis` (PostGIS é não-trusted).
- `ALTER EXTENSION postgis SET SCHEMA` → `0A000` (não suportado) → relocação exige disable+re-enable.
- Nenhuma coluna `geometry`/`geography` em uso → o CASCADE do disable remove SÓ `idx_operational_zones_geog` (recriado por esta migração).

**Ordenação sênior — sem janela de outage por timing de migração:**

`20260810000001` apenas estende `search_path` (`public` → `public, extensions`) e é inofensiva com PostGIS ainda em `public` (`extensions` já no path, `ST_*` resolve de `public`). Deployá-la ANTES da janela torna a recuperação dos RPCs **instantânea** no re-enable — elimina a dependência "aplicar migração na mesma janela". O único gap real passa a ser os segundos entre *disable* e *re-enable*.

**Passos:**
0. (pré-janela, fora de manutenção) **Deploy de `20260810000001`** com PostGIS ainda em `public` (`supabase db push` / merge). No-op funcional; prepara o search_path.
1. (app) pausar ingest GPS / janela de manutenção.
2. (Dashboard) **Database → Extensions → postgis → Disable** — confirma CASCADE (só `idx_operational_zones_geog` cai).
3. (Dashboard) **Re-enable postgis**, **Schema = `extensions`** — RPCs voltam NA HORA (search_path já contém `extensions`, pois o passo 0 já está live).
4. (app) retomar ingest.
5. (follow-up, **fora do caminho crítico** — só performance) re-deploy de `20260810000001` para recriar o índice GIST (`CREATE INDEX IF NOT EXISTS`). Até lá os RPCs funcionam por seq scan (zonas são poucas por org).

**Determinismo (INV-15):** a relocação mantém as MESMAS funções PostGIS (`ST_Distance`/`ST_DWithin`/`ST_MakePoint`) — resultados byte-idênticos aos verdicts já selados. Por isso a relocação é preferível a reescrever a distância em SQL puro (haversine), que alteraria a matemática de geofence e quebraria o replay byte-idêntico de telemetria histórica (INV-15/INV-21). Rejeitado por decisão de Conselho.

> Equivalente SQL (referência — NÃO executável por `postgres`, é o que o Dashboard roda internamente):
> ```sql
> DROP EXTENSION postgis CASCADE;            -- cascateia SÓ o índice GIST
> CREATE EXTENSION postgis SCHEMA extensions;
> ```

**Postura B (residual aceito — fallback / standing):** se o seletor de schema não existir ou o risco da janela não for aceitável, manter o guard interim `20260810000000` como controle **durável**. O advisor permanece amarelo, mas: vetor de escrita fechado (`42501`), confidencialidade NENHUMA (constantes geodésicas públicas, sem `organization_id`). Registrado no `20260810000002_spatial_ref_sys_accept_risk_record.md`.

**Nota de remoção do controle interim:** após a relocação, `public.spatial_ref_sys` deixa de existir e o trigger `guard_spatial_ref_sys_writes_trg` é removido automaticamente pelo DROP (DDL não dispara trigger de DML). Sem migração de limpeza. Registrar a data da janela no `20260810000002_spatial_ref_sys_accept_risk_record.md`.

---

## Verificação Automatizada (pré-relocação — roda agora)

```bash
make test-db
```
`20260810000001_..._test.sql` (7):
1. `check_and_close_execution_autonomously` tem `search_path` incluindo `extensions`.
2. `process_gps_for_execution_transitions` idem.
3. índice GIST `idx_operational_zones_geog` presente.
4. closer com nil UUID → sentinela `not_found` (prova `ST_*` resolve).
5. FSM GPS com nil UUID → sentinela `no_asset` (prova `ST_DWithin`/`ST_MakePoint` resolvem).
6. `spatial_ref_sys` sem coluna `organization_id`.
7. contagem `spatial_ref_sys >= 8300`.

---

## Verificação Manual Pós-Relocação (após ticket aplicar)

> Não automatizável até a relocação física. Executar após o passo 3 do runbook.

### Teste R.1 — catálogo saiu de `public`
```sql
SELECT to_regclass('public.spatial_ref_sys');      -- esperado: NULL
SELECT to_regclass('extensions.spatial_ref_sys');  -- esperado: NOT NULL
```

### Teste R.2 — anon perdeu alcance
```sql
SELECT has_table_privilege('anon', 'extensions.spatial_ref_sys', 'SELECT'); -- esperado: false
```

### Teste R.3 — advisor limpo
Re-rodar Supabase Advisors → `rls_disabled_in_public` em `spatial_ref_sys` **ausente**.

### Teste R.4 — smoke dos 2 RPCs (sem "function ST_* does not exist")
```sql
SELECT public.check_and_close_execution_autonomously(gen_random_uuid(), '__smoke__');
SELECT public.process_gps_for_execution_transitions(gen_random_uuid(), '__smoke__', 0, 0);
```
* **Esperado:** sentinelas `not_found` / `no_asset` (sem erro de resolução de função).

---

## Matriz de Aceitação

| Cód | Validação | Esperado | Status |
|:---|:---|:---|:---:|
| RL-01 | closer search_path inclui extensions | true | `[x]` |
| RL-02 | FSM search_path inclui extensions | true | `[x]` |
| RL-03 | índice GIST presente | true | `[x]` |
| RL-04 | closer nil UUID → `not_found` | sentinela | `[x]` |
| RL-05 | FSM nil UUID → `no_asset` | sentinela | `[x]` |
| RL-06 | spatial_ref_sys sem org_id | 0 | `[x]` |
| RL-07 | contagem >= 8300 | true | `[x]` |
| RL-08 | **pós-reloc:** public ausente / extensions presente | NULL / NOT NULL | `[ ]` (gated) |
| RL-09 | **pós-reloc:** anon SELECT em extensions.spatial_ref_sys | false | `[ ]` (gated) |
| RL-10 | **pós-reloc:** advisor limpo | ausente | `[ ]` (gated) |
| RL-11 | **pós-reloc:** smoke 2 RPCs | sentinelas | `[ ]` (gated) |

---

## Rollback

Idempotente: aplicar com PostGIS ainda em `public` é inofensivo (adição de `extensions` ao search_path + `CREATE INDEX IF NOT EXISTS`). Se a relocação precisar reverter, `supabase_admin` roda `DROP EXTENSION postgis CASCADE; CREATE EXTENSION postgis SCHEMA public;` e reaplica `20260704000001`/`20260704000003` — o search_path estendido continua válido (`public` ainda no path).
