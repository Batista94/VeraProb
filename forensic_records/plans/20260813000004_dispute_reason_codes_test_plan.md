# Plano de Testes — dispute_reason_codes

**Migração:** `supabase/migrations/20260813000004_dispute_reason_codes.sql`
**Teste pgTAP:** `supabase/tests/20260813000004_dispute_reason_codes_test.sql`
**Invariantes:** INV-1 (escopo org_id), INV-2 (RLS via `app_metadata.org_id`),
INV-3 (catálogo fechado — sem criação client-side), INV-6 (`TIMESTAMPTZ`),
INV-22 (isolamento tenant), INV-DB (tabela nova com grants explícitos).
**Risco:** Médio — taxonomia estruturada que alimenta BI e a obrigatoriedade de
`reason_code` nas RPCs. Falha = código vertical-específico vaza (B6), ou tenant
vê código privado de outro (INV-22), ou cliente cria código corrompendo a
taxonomia global (Q2).

## Objetivo

`dispute_reason_codes` é o catálogo global **fechado** (Q2) de motivos de disputa.
B6: `code` é agnóstico de vertical (sobrevive troca de indústria); termo de
transporte vive só em `label_pt`/`label_en`. Linhas globais (`organization_id IS
NULL`) visíveis a todo tenant; linhas org-scoped (fase futura de custom-codes)
isoladas por RLS. Sem policy de INSERT → criação client-side bloqueada em v1.

## Estratégia

Comportamental + estrutural. Seeds rodam como `postgres` (bypass RLS) para
montar o catálogo global (16 seeds via migração) + um código privado de Org B.
RLS verificada sob sessão `authenticated` mockada (`SET LOCAL request.jwt.claims`
+ `SET LOCAL ROLE authenticated`), padrão dos testes de RPC. Falha de INSERT
sob RLS sem policy = `42501` (anti-oracle, paridade com wrong-org).

## Casos pgTAP (plan = 13)

**Estrutura**
1. Tabela `dispute_reason_codes` existe.
2. Possui PRIMARY KEY (`code`).
3. RLS habilitada (`relrowsecurity`, INV-2).

**Catálogo / seed**
4. Exatamente 16 códigos globais (`organization_id IS NULL`) — catálogo fechado Q2.
5. Códigos agnósticos B6 presentes (`THIRD_PARTY_INCIDENT`, `OPERATOR_EMERGENCY`,
   `ASSET_BREAKDOWN`, `REGULATORY_INTERVENTION`).
6. CHECK `chk_reason_category` rejeita categoria fora da taxonomia → `23514`.

**Grants (INV-DATA-API-GRANT)**
7. `authenticated` pode `SELECT`.
8. `anon` NÃO pode `SELECT` (C6).
9. `service_role` pode `SELECT` (ALL).

**RLS (sessão authenticated, Org RC)**
10. Tenant vê os 16 códigos globais (`drc_select_global`).
11. Org RC NÃO vê o código privado de Org B (`ORGB_PRIVATE`) — INV-22.
12. INSERT client-side bloqueado (sem policy de INSERT) → `42501` (Q2).

**Defaults**
13. `applies_to` default `'ALL'`.

## Notas

- PK é `code` isolado; `uq_reason_code_org (code, organization_id)` é a unique
  secundária. Por isso o seed privado de Org B usa um `code` distinto
  (`ORGB_PRIVATE`) — não colide com a PK do catálogo global.
- Tabela nova exposta à Data API → `supabase/types.database.ts` regenerado e
  commitado junto (via `sync_db_types.sh` no caminho de migração staged).
- Sem policy de INSERT/UPDATE em v1 (Q2). Fase futura de custom-codes DEVE exigir
  `organization_id IS NOT NULL` em qualquer policy de INSERT (M-qa), senão códigos
  org-scoped vazariam globalmente.
