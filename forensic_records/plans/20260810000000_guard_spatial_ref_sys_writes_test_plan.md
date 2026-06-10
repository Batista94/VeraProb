# Plano de Testes — 20260810000000_guard_spatial_ref_sys_writes

**Migração:** `supabase/migrations/20260810000000_guard_spatial_ref_sys_writes.sql`
**Invariantes:** INV-2 (defesa em profundidade em tabela do schema `public`), INV-22 (redução de superfície de ataque). INV-DB: sem DDL destrutivo.
**Risco:** Médio — controle compensatório INTERIM que fecha o vetor de escrita anônima em `public.spatial_ref_sys` enquanto o PostGIS reside em `public`. Não corrige a raiz (relocação = `20260810000001` + ticket Supabase).
**pgTAP:** `supabase/tests/20260810000000_guard_spatial_ref_sys_writes_test.sql` (7 testes).

---

## Contexto — por que um trigger, não REVOKE/RLS

O advisor `rls_disabled_in_public` dispara em `public.spatial_ref_sys` (catálogo PostGIS, ~8500 linhas EPSG/SRID). A tabela pertence a `supabase_admin` e é membro da extensão `postgis`. O papel de migração `postgres` é **não-owner / não-superuser / não-grantor**, logo NÃO pode:

- `ALTER TABLE … ENABLE ROW LEVEL SECURITY` (owner-only → no-op);
- `REVOKE INSERT/UPDATE/DELETE/TRUNCATE … FROM anon, authenticated` (grantor-only → `WARNING 01006` no-op silencioso — confirmado via `aclexplode`);
- `ALTER EXTENSION postgis SET SCHEMA extensions` (`0A000` — PostGIS não suporta).

**O único lever executável no tier `postgres`:** o papel detém o privilégio `TRIGGER` sobre a tabela (verificado no ACL dump). Um trigger `BEFORE … FOR EACH STATEMENT` que faz `RAISE EXCEPTION` para papéis de cliente bloqueia a mutação antes de qualquer dano, sem `supabase_admin`.

**Vetor fechado:** chave `anon` extraída → Data API `DELETE`/`TRUNCATE` sobre o catálogo SRID → degradação dos RPCs espaciais de GPS (autonomous closer / auto-start). Severidade Integridade/Disponibilidade = MÉDIA. **Sem dados de tenant** (`spatial_ref_sys` não tem `organization_id`) → INV-1/INV-22 não violados.

## Escopo por papel (maintenance nunca bloqueada)

| Papel | INSERT/UPDATE/DELETE/TRUNCATE em spatial_ref_sys |
|-------|--------------------------------------------------|
| `anon`, `authenticated` | **BLOQUEADO** (`42501 insufficient_privilege`) |
| `supabase_admin`, `postgres`, `service_role`, demais | **PERMITIDO** (upgrade PostGIS roda como `supabase_admin` via `populate_spatial_ref_sys()`) |

A aplicação nunca escreve nessa tabela (dado de referência) → bloquear papéis de cliente tem impacto funcional zero.

## Ciclo de vida

Controle INTERIM. A raiz é a relocação do PostGIS para `extensions` (`20260810000001` + ticket Supabase). Quando `supabase_admin` roda `DROP EXTENSION postgis CASCADE`, `public.spatial_ref_sys` é removida e o trigger some automaticamente (DROP de DDL não dispara triggers de DML) — **sem migração de limpeza**.

---

## Passo a Passo de Verificação (psql / Supabase Studio)

> Execute cada bloco inteiro de uma vez para preservar role.

### Teste G.1 — função guard existe
```sql
SELECT proname FROM pg_proc
WHERE proname = 'guard_spatial_ref_sys_writes' AND pronamespace = 'public'::regnamespace;
```
* **Esperado:** 1 linha.

### Teste G.2 — trigger anexado
```sql
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'public.spatial_ref_sys'::regclass
  AND tgname = 'guard_spatial_ref_sys_writes_trg' AND NOT tgisinternal;
```
* **Esperado:** 1 linha.

### Teste G.3 — anon DELETE bloqueado
```sql
BEGIN;
SET LOCAL ROLE anon;
DELETE FROM public.spatial_ref_sys WHERE srid = -99999;
ROLLBACK;
```
* **Esperado:** `ERROR 42501: spatial_ref_sys is a read-only PostGIS reference catalog: DELETE denied for role anon`.

### Teste G.4 — authenticated UPDATE bloqueado
```sql
BEGIN;
SET LOCAL ROLE authenticated;
UPDATE public.spatial_ref_sys SET auth_name = auth_name WHERE srid = -99999;
ROLLBACK;
```
* **Esperado:** `ERROR 42501: … UPDATE denied for role authenticated`.

### Teste G.5 — papel privilegiado NÃO bloqueado
```sql
BEGIN;
DELETE FROM public.spatial_ref_sys WHERE srid = -99999; -- no-op 0 linhas, sem erro
ROLLBACK;
```
* **Esperado:** sucesso (0 linhas afetadas; guard libera `postgres`).

### Teste G.6 — sem coluna de tenant
```sql
SELECT count(*) FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'spatial_ref_sys' AND column_name = 'organization_id';
```
* **Esperado:** `0` (sem dado de tenant; INV-22 N/A).

### Teste G.7 — contagem de linhas (detector de TRUNCATE)
```sql
SELECT count(*) >= 8300 FROM public.spatial_ref_sys;
```
* **Esperado:** `true`.

---

## Automação

```bash
make test-db
```
- `20260810000000_guard_spatial_ref_sys_writes_test.sql` (7) — estrutura + comportamento por papel + invariantes de catálogo.

---

## Matriz de Aceitação

| Cód | Validação | Esperado | Status |
|:---|:---|:---|:---:|
| GD-01 | função guard existe | 1 | `[x]` |
| GD-02 | trigger anexado | 1 | `[x]` |
| GD-03 | anon DELETE | `42501` bloqueado | `[x]` |
| GD-04 | authenticated UPDATE | `42501` bloqueado | `[x]` |
| GD-05 | postgres DELETE | permitido (no-op) | `[x]` |
| GD-06 | sem coluna org_id | 0 | `[x]` |
| GD-07 | contagem >= 8300 | true | `[x]` |
| GD-08 | suíte pgTAP | PASS | `[ ]` |

---

## Rollback

Remoção do controle só faz sentido APÓS a relocação (`20260810000001`). Para reverter antes disso, `DROP TRIGGER guard_spatial_ref_sys_writes_trg ON public.spatial_ref_sys` em migração forward — porém reabre o vetor de escrita anônima e seria sinalizado pela revisão do Conselho. O caminho correto é a relocação, que torna o trigger obsoleto automaticamente.
