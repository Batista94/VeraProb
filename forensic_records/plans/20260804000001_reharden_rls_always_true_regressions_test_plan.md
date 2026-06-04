# Plano de Testes — 20260804000001_reharden_rls_always_true_regressions

**Migração:** `supabase/migrations/20260804000001_reharden_rls_always_true_regressions.sql`
**Invariantes:** INV-1, INV-2, INV-3, INV-22, INV-26
**Risco:** Alto — fecha regressões de RLS always-true reintroduzidas por migrações posteriores ao endurecimento `20260602000001`.
**pgTAP:** `supabase/tests/20260804000001_reharden_rls_always_true_regressions_test.sql` (7 testes) + standing `supabase/tests/inv22_always_true_policy_invariant_test.sql` (3 testes).

---

## Contexto — Cadeia de Regressões

O endurecimento `20260602000001` removeu políticas permissivas `USING(true)/WITH CHECK(true)`. Migrações **posteriores** (append-only) as reintroduziram silenciosamente, anulando a intenção de segurança:

| Regressão | Origem | Efeito | Severidade |
|-----------|--------|--------|------------|
| `tpl_service_all` recriada `{public}` USING(true) | `20260614000001_telegram_self_link.sql:50-53` | + GRANT anon (`20260527170000`) sem deny-all anon → **anon (não autenticado) lê/escreve `telegram_pending_links` cross-tenant** | **CRÍTICO** (INV-1/22/26) |
| `tsq_insert_service` recriada `{public}` WITH CHECK(true) | `20260616000001_evidence_compliance_status.sql:95-98` | Latente (sem GRANT INSERT a anon/authenticated hoje), mas viola lint + landmine | MÉDIA (INV-1/3/22) |
| `spatial_ref_sys` legível por client roles | `20260602000001` (REVOKE no-op) | Enumeração de SRID público | BAIXA (lint; **sem dados de tenant**) |

`authenticated` já estava corretamente bloqueado em `telegram_pending_links` (deny-all RESTRICTIVE vence a permissiva). O vetor vivo era o **anon**.

---

## §A — spatial_ref_sys: por que NÃO há REVOKE executável

`spatial_ref_sys` pertence a `supabase_admin`; seus grants (incl. `SELECT TO PUBLIC` do PostGIS) foram concedidos por `supabase_admin`. Migrações rodam como `postgres`, que **não é superuser nem membro de `supabase_admin`** (verificado: `rolsuper=false`, `pg_has_role(postgres,supabase_admin,MEMBER)=false`). Portanto qualquer `REVOKE ... FROM PUBLIC/anon/authenticated` é no-op silencioso (`WARNING 01006: no privileges could be revoked`). O REVOKE de `20260602000001` sempre foi ineficaz — não repetimos o no-op.

**Risco real:** `spatial_ref_sys` contém apenas referência geodésica pública (srid, auth_name, auth_srid, srtext, proj4text) — **sem `organization_id`, sem linhas de tenant, sem PII**. INV-22 não é violado. Mitigação efetiva (mover PostGIS p/ schema dedicado ou excluir da exposição PostgREST) é operação de plataforma com `supabase_admin`, rastreada à parte. O standing test garante a ausência de coluna de tenant.

---

## Passo a Passo de Verificação (psql / Supabase Studio)

> Execute cada bloco inteiro (BEGIN…ROLLBACK) de uma vez para preservar role/claims.

### Teste A.1 — anon NÃO acessa `telegram_pending_links` (CRÍTICO fechado)
```sql
BEGIN;
SET LOCAL ROLE anon;
SELECT * FROM public.telegram_pending_links LIMIT 1;
ROLLBACK;
```
* **Esperado:** `ERROR: permission denied for table telegram_pending_links` (GRANT anon revogado).

### Teste A.2 — `tpl_service_all` ausente
```sql
SELECT count(*) FROM pg_policies
WHERE schemaname='public' AND tablename='telegram_pending_links' AND policyname='tpl_service_all';
```
* **Esperado:** `0`.

### Teste A.3 — deny-all anon RESTRICTIVE presente
```sql
SELECT permissive FROM pg_policies
WHERE tablename='telegram_pending_links' AND policyname='deny-all anon: telegram_pending_links';
```
* **Esperado:** `RESTRICTIVE`.

### Teste A.4 — `tsq_insert_service` apenas service_role
```sql
SELECT roles FROM pg_policies
WHERE tablename='telegram_status_queries' AND policyname='tsq_insert_service';
```
* **Esperado:** `{service_role}`.

### Teste A.5 — service_role mantém operação (fluxo do bot intacto)
```sql
SELECT has_table_privilege('service_role','public.telegram_pending_links','INSERT');
```
* **Esperado:** `true` (service_role bypassa RLS; webhook + RPCs SECURITY DEFINER inalterados).

### Teste A.6 — varredura always-true (deve retornar 0)
```sql
SELECT tablename, policyname FROM pg_policies
WHERE schemaname='public' AND permissive='PERMISSIVE'
  AND (qual='true' OR with_check='true')
  AND (roles::text[] && ARRAY['public','authenticated','anon']::text[] OR roles::text='{}')
  AND tablename IN ('telegram_pending_links','telegram_status_queries');
```
* **Esperado:** **0 linhas**.

---

## Automação

```bash
make test-db
```
- `20260804000001_..._test.sql` (7) — estado pós-migração.
- `inv22_always_true_policy_invariant_test.sql` (3) — **standing guard** independente de timestamp; pega qualquer always-true futura na allowlist de tabelas tenant-facing + ausência de coluna de tenant em `spatial_ref_sys`.

---

## Matriz de Aceitação

| Cód | Validação | Esperado | Status |
|:---|:---|:---|:---:|
| RH-01 | anon SELECT em `telegram_pending_links` | permission denied | `[x]` |
| RH-02 | `tpl_service_all` removida | 0 | `[x]` |
| RH-03 | deny-all anon RESTRICTIVE | presente | `[x]` |
| RH-04 | `tsq_insert_service` roles | `{service_role}` | `[x]` |
| RH-05 | service_role INSERT preservado | true | `[x]` |
| RH-06 | varredura always-true | 0 linhas | `[x]` |
| RH-07 | `spatial_ref_sys` sem coluna org_id | 0 | `[x]` |
| RH-08 | suíte pgTAP completa | PASS (410) | `[x]` |

---

## Rollback

As migrações de origem (`20260614`, `20260616`) NÃO são editadas (append-only). Para reverter este endurecimento, criar nova migração forward restaurando as políticas — porém isso reabre o vetor anon crítico e seria bloqueado pelo standing test + regra de scanner `ALWAYS-TRUE-RLS-POLICY`.
