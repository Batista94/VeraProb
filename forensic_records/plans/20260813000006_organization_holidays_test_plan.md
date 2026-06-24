# Plano de Testes — organization_holidays

**Migração:** `supabase/migrations/20260813000006_organization_holidays.sql`
**Teste pgTAP:** `supabase/tests/20260813000006_organization_holidays_test.sql`
**Invariantes:** INV-1 (escopo org_id), INV-2 (RLS via `app_metadata.org_id`),
INV-6 (`TIMESTAMPTZ`), INV-22 (isolamento tenant), INV-DB (tabela nova com grants
explícitos; sem DELETE de cliente — soft-delete).
**Risco:** Médio — calendário de dias úteis alimenta o prazo de SLA da disputa.
Falha = prazo determinístico quebra (fim de semana/feriado não pulado), locale
pack BR vaza no core agnóstico (H4), ou tenant vê feriado de outro (INV-22).

## Objetivo

`organization_holidays` é o calendário por-tenant de dias não-úteis. O core
agnóstico só embarca a **tabela vazia** + as funções de cálculo. H4:
`seed_brazilian_national_holidays` é um **LOCALE PACK** — NUNCA invocado pelo
provisionamento genérico; só `service_role` o executa explicitamente. M-arch:
soft-delete (`deleted_at`), sem grant de DELETE ao cliente. Q1:
`_compute_business_day_deadline` é determinística (ISODOW Sáb=6 Dom=7 + feriados).

## Estratégia

Estrutural + comportamental, como `postgres` (superusuário) dentro de
`BEGIN/ROLLBACK`. Funções internas estão com `REVOKE ALL` de todos os roles de
API → chamadas diretas só rodam como superusuário (cobertura de cálculo) e os
privilégios EXECUTE são verificados via `has_function_privilege` (prova H4). RLS
verificada sob sessão `authenticated` mockada (`SET LOCAL request.jwt.claims` +
`SET LOCAL ROLE authenticated`). INSERT sem papel `TENANT_ADMIN` ou cross-org =
`42501` (anti-oracle, paridade com wrong-org).

Datas-âncora (determinismo, sem depender de relógio): 2026-01-01 = quinta →
2026-06-12 = sexta. `+1` dia útil a partir de sexta pula Sáb/Dom e cai na
segunda (2026-06-15); com feriado em 2026-06-15, cai na terça (2026-06-16).
Páscoa 2026 = 05-abr (âncora verificada).

## Casos pgTAP (plan = 23)

**Estrutura (5)**
1. Tabela `organization_holidays` existe.
2. Possui PRIMARY KEY.
3. RLS habilitada (`relrowsecurity`, INV-2).
4. UNIQUE `uq_org_holiday_date (organization_id, holiday_date)` existe.
5. Coluna `deleted_at` existe (M-arch soft-delete).

**Grants (4)**
6. `authenticated` pode `SELECT`.
7. `authenticated` NÃO pode `DELETE` (M-arch — só soft-delete).
8. `service_role` tem `ALL` (inclui `DELETE`).
9. `anon` NÃO pode `SELECT`.

**Funções de cálculo (6)**
10. `_compute_easter(2026)` = `2026-04-05` (âncora verificada).
11. Prazo de dia útil pula fim de semana (sexta +1 dia útil = segunda).
12. `p_business_days <= 0` → fim do dia da data inicial.
13. Prazo pula feriado do tenant (segunda feriado → terça).
14. `seed_brazilian_national_holidays` insere/retorna 12 feriados.
15. As 12 linhas semeadas têm `is_national = TRUE`.

**Locale pack / privilégios de função (3, H4)**
16. `authenticated` NÃO pode `EXECUTE` o seed locale-pack (H4).
17. `service_role` pode `EXECUTE` o seed (invocação explícita só).
18. `authenticated` NÃO pode `EXECUTE` a função interna de prazo.

**RLS (5, sessão authenticated, Org HA)**
19. Org HA NÃO vê feriados da Org HB (INV-22).
20. Org HA vê o próprio feriado (`oh_select_own_org`).
21. `TENANT_ADMIN` pode INSERT feriado do próprio org (`lives_ok`).
22. Não-admin (`DISPATCHER`) NÃO pode INSERT → `42501`.
23. `TENANT_ADMIN` NÃO pode INSERT cross-org → `42501` (INV-22).

## Notas

- FK `organization_id → organizations(id)` (criada em
  `20260305171000_multi_tenancy_foundation.sql`).
- Funções `STABLE`/`IMMUTABLE` com `SET search_path = public, extensions`
  (anti-hijack). `_compute_business_day_deadline` lê `organization_holidays`
  como `SECURITY DEFINER` → bypassa RLS de leitura interna por desenho (cálculo
  do prazo independe da sessão do chamador).
- Tabela nova exposta à Data API → `supabase/types.database.ts` regenerado e
  commitado junto.
- Ordem dos testes de prazo: o teste de fim-de-semana roda ANTES de inserir o
  feriado de 2026-06-15; o seed BR roda na Org HB para não poluir a janela de
  dias úteis da Org HA.
