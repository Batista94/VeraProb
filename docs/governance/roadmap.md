# PactaFlow — Roadmap Estratégico

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---------|--------|
| Testes | 360 passing · 0 falhas ✅ |
| Análise estática | 0 erros · 67 infos (`prefer_const` — baixa prioridade) |
| Precisão financeira | `Money` (centavos BIGINT) em todo o stack — invariante enforced ✅ |
| CI/CD | Não existe (Phase 8) |
| Ambientes | Dev local único. Sem staging, sem prod. |
| `strict-casts` | Desabilitado — ~80 issues de `dynamic` nos repos Postgres (Phase 8) |
| Sprint 5.11 | **CONCLUÍDA** — Fases A-I implementadas (Wizard refatorado, Clona Contrato, Templates SLA, Contractor Label). |
| Sprint 5.12 Phase D | **CONCLUÍDA** — Refinamento, UTC, Schema e Segurança RLS. ✅ |
| Banco de dev | Todas as migrations aplicadas — `20260311000000` · `20260311000002` · `20260311000003` · `20260312000001` · `20260312000002` · `20260312000003` · `20260313000001` ✅ |

---

## Fases Pendentes

> Ordem de execução é obrigatória — fases não podem ser puladas.

---

#### [x] 5.12 — Final Operational Validation
> **Renomeado de "5.10 Validation Consolidada" em 2026-03-12.** O fluxo de cadastro prévio de
> zonas foi considerado burocrático pelo PO e substituído pelo fluxo Just-in-Time (Sprint 5.12).
> A validação manual agora cobre o fluxo completo **com criação inline de zonas**.
>
> **✅ BLOQUEADOR RESOLVIDO:** Integridade e Segurança (Bloco 1) 100% concluído.

---

### BLOCO 1 — CONCLUÍDO ✅
**Gerado:** 2026-03-14 | **Estado:** 100% resolvido.
*Blocos 2–4 da Sprint 5.13 liberados para planejamento.*

#### 1.1 — Auditoria RLS: organization_id em contractual_service_executions [DONE]
- **Status:** Causal linkage corrigido com organization_id. Política atual (auth.uid()) válida para dev. Dívida: migrar para JWT claim em Phase 6.3.
- **Files:** `lib/infrastructure/sla_audit/postgres_plan_declaration_repository.dart`, `lib/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart`

#### 1.2 — Precisão Financeira: double → Money/int (Penalidades) [DONE]
- **Status:** `Money.multiplyByBps(int bps)` adicionado. Basis points (int) adotados.
- **Files:** `lib/domain/sla_audit/sla_penalties.dart`, `lib/domain/value_objects/money.dart`

#### 1.3 — Soberania de Domínio: Remover Flutter Primitives [DONE]
- **Status:** `flutter/material.dart` removido do enum; `IncidentStatusUiMapper` criado.
- **Files:** `lib/domain/enums/incident_lifecycle_status.dart`, `lib/features/shared/mappers/incident_status_ui_mapper.dart` [NEW]

#### 1.4 — Padronização UTC: DateTime.now() → toUtc() [DONE]
- **Status:** 12 violações corrigidas em domain/application/infrastructure. System-wide UTC enforced.

---

### Sprint 5.13 — Post-Validation Hardening
**Planejável em paralelo ao Bloco 1, mas implementável apenas após sua conclusão.**

#### BLOCO 2 — Taxonomia de Zonas e Isolamento de Ativos
- **[DONE] 2.1 — Zone Taxonomy:** `enum ZoneScope { global, exclusive }` + getter `scope` em `OperationalZone`. Migration `20260315000001_zone_scope.sql` aplicada (coluna gerada + index + constraint).
- **[DONE] 2.2 — Contextual Zone Filter:** `filterZones()` em `ZoneTypeAheadField` usa `z.scope == ZoneScope.global` — semântica formal aplicada.
- **[DONE] 2.3 — JIT Inline Zone Creation:** Botão Cancelar sempre habilitado. `_isCancelled` flag + `mounted` guard em `_submit()` — sem race condition.
- **[DONE] 2.4 — Zero-Friction Zone Field:** Clear button (X) no `ZoneTypeAheadField`. Swap `Icons.swap_vert` entre origem/destino no Step 1.
- **Personas:** `architect`, `senior_engineer`, `ux_operations`

#### BLOCO 5 — Regression Fixes (Pré-requisito para Blocos 3 e 4)
> **Encontrado em:** Testes manuais pós-Bloco 2 (2026-03-15). Bug 5.1 é bloqueante — impede publicação de qualquer plano B2B.

- **[ ] 5.1 — RLS Fix: contractual_service_executions (BLOQUEANTE)**
  - Política atual usa bootstrap antipattern `auth.uid()` (INV-10 violado). Org UUID ≠ User UUID em qualquer tenant real → 42501 em todos os publishes B2B.
  - **Ação:** Migration `20260316000001_cse_rls_fix.sql` — DROP policy atual + CREATE com `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid`.
  - **PO confirmar nome da política atual via Supabase Dashboard antes de executar.**
  - **Files:** `supabase/migrations/20260316000001_cse_rls_fix.sql` [NEW]

- **[DONE] 5.2 — Geofence Callback: estado visual não atualiza após configurar geofence ✅**
  - `onGeofenceConfigured` é `VoidCallback` — descarta o objeto `saved` retornado pelo modal. `selectedZone` no pai fica com objeto antigo (sem geofence). Ícone e aviso não atualizam.
  - **Ação:** Alterar assinatura para `ValueChanged<OperationalZone>`, propagar `saved` ao pai para atualizar `_selectedOriginZone`/`_selectedDestinationZone`.
  - **Files:** `lib/features/admin/presentation/widgets/zone_type_ahead_field.dart`, `lib/features/admin/presentation/screens/declare_contract_plan_form.dart`

- **[DONE] 5.3 — JIT Stale Data: zona criada não aparece no autocomplete após limpar ✅**
  - `onInvalidateZones` retorna imediatamente após `ref.invalidate()` sem aguardar o refetch. Botão "+ Criar zona" re-aparece para nomes parciais (exact-match vs contains), permitindo tentativa de criar zona duplicada.
  - **Ação:** `onInvalidateZones` deve ser `Future<void>` que aguarda o provider resolver. Após criação JIT, manter zona selecionada (não forçar `onChanged(null)`).
  - **Files:** `lib/features/admin/presentation/widgets/zone_type_ahead_field.dart`, `lib/features/admin/presentation/screens/declare_contract_plan_form.dart`

- **Personas:** `qa_security` (5.1), `senior_engineer` + `ux_operations` (5.2, 5.3)

#### BLOCO 3 — Fluxo de Declaração B2B
- **3.1 — Stepper Clicável:** Implementar `onStepTapped`. Permitir voltar, bloquear avanço não validado.
- **3.2 — Contexto no Step 2:** Exibir banner "Origem → Destino" durante configuração de horários.
- **3.3 — Ciclo Industrial:** Suporte a Return Shifts em datas específicas ou semanas diferentes (`weekOffset`).
- **Personas:** `senior_engineer`, `ux_operations`, `architect`

#### BLOCO 4 — Compliance e Penalidades
- **4.1 — Step 3 Refinement:** Renomear para "Acordo de Penalidades". Adicionar campo `gracePeriodMinutes`.
- **4.2 — Step 4: Exposição de Risco Financeiro:** Novo resumo calculado antes de publicar (Receita Protegida, Exposição Máx no-show, Penalidade máx por viagem).
- **Personas:** `Full Council`, `ux_operations`, `senior_engineer`

---

### [ ] Phase 6 — Administration & Tenant Self-Service


**Por que depois de Phase 5:** Com a jornada do operador completa (Phase 5), a próxima barreira
é escalar: cada novo cliente hoje requer intervenção manual do desenvolvedor para ser cadastrado.
Phase 6 torna o produto auto-suficiente para N tenants.

**Objetivo:** Qualquer empresa de transporte pode se cadastrar, configurar suas regras SLA,
convidar sua equipe e começar a operar — sem nenhuma intervenção do desenvolvedor.

#### [ ] 6.1 — Design Specification
**Artefato:** `docs/architecture/10_administration_tenant_onboarding_design.md`

Cobrir obrigatoriamente:
- **Organization Management:** criação de organização, fuso horário, moeda, logo
- **RBAC model:** 3 roles — `Admin` (configuração total) · `Operator` (OCC + contratos) · `Auditor` (read-only + exports)
- **User invitation flow:** convite por email via Supabase Auth, aceite com criação de senha
- **Rule Configuration Studio:** editor visual para parâmetros SLA (`min_dwell_seconds`, geofence radius, tolerâncias)
- **Asset onboarding:** cadastro de veículos, motoristas, rotas via UI
- **First Run flow:** jornada completa do zero até primeiro plano avaliado
- **Permissões por role:** mapeamento de cada ação a qual role pode executar

#### [ ] 6.2 — Council Review
Validar antes de implementar:
- Tenant recém-criado não acessa dados de tenants existentes em nenhum momento
- `Operator` recebe 403 ao tentar acessar endpoints de configuração de regras
- `Auditor` não consegue acionar nenhuma escrita — nem diretamente, nem via UI
- Rule Studio não edita versões de regras já referenciadas em planos ativos (imutabilidade retroativa)
- `organization_id` de qualquer novo recurso derivado do JWT do usuário autenticado, nunca de campo livre

#### [ ] 6.3 — Implementation
- **SQL:** `organizations`, `user_organization_memberships`, `invitations`, RLS por role, policies por recurso
- **Domain:** `OrganizationMembership`, `UserRole`, `Invitation`, `RuleConfiguration`
- **Application:** `InviteUserCommand`, `AcceptInvitationCommand`, `ConfigureRuleSetCommand`, `RevokeAccessCommand`
- **Infrastructure:** Repositórios Postgres + Supabase Auth hooks para role injection no JWT
- **Presentation:**
  - Admin Panel (settings da org, lista de usuários, convites pendentes)
  - Rule Configuration Studio (formulário visual por tipo de regra SLA)
  - Asset Manager (veículos, motoristas, rotas com CRUD completo)

#### [ ] 6.4 — Validation

**Cenários automatizados:**
- Cenário 6.1: Org A criada via UI não enxerga dados de Org B em nenhuma query
- Cenário 6.2: Role `Operator` — tenta editar regra SLA → 403; acessa OCC → 200
- Cenário 6.3: Role `Auditor` — tenta declarar plano → 403; visualiza relatório → 200
- Cenário 6.4: Regra alterada hoje não muda resultado de snapshot já fechado (deterministic replay)

**⚠️ Testes Manuais Obrigatórios (não automatizáveis por natureza):**
> RBAC real, convite por email e First Run requerem sessão de browser com usuário autenticado.
> Estes cenários NÃO podem ser cobertos por `flutter test`.

- [ ] **Convite por email:** Admin convida novo usuário → verificar que email chega, link funciona, usuário cria senha e é associado à org correta no JWT
- [ ] **RBAC — Operator:** logar como `Operator` → tentar acessar Admin Panel → confirmar que é bloqueado ou que botões de configuração estão ausentes/desabilitados
- [ ] **RBAC — Auditor:** logar como `Auditor` → tentar declarar plano → confirmar que ação não está disponível; acessar relatórios → confirmar que funciona
- [ ] **RBAC — Admin:** logar como `Admin` → verificar que todas as seções estão acessíveis
- [ ] **Rule Configuration Studio:** criar regra SLA via formulário visual → confirmar que nova versão de regra aparece no histórico, não substitui a anterior
- [ ] **Regra imutável:** editar regra referenciada por plano ativo → confirmar que UI bloqueia ou cria nova versão separada
- [ ] **First Run completo (Cenário 6.5):** org criada → usuário convidado → regra configurada → plano declarado → avaliação executada → verificar cada etapa no Supabase dashboard

- **Compliance Report:** `docs/governance/compliance/phase6_compliance_report.md`

---

### [ ] Phase 7 — Evidence & Audit Exports

**Por que depois de Phase 6:** Exportações são o produto que o cliente entrega ao seu próprio cliente
(empresa de transporte entregando relatório de SLA ao contratante). Só faz sentido gerar esse produto
quando a plataforma tem clientes reais com dados reais fluindo.

**Nota:** Fundação parcialmente implementada — `BillingCycleReport` domain entity completo com
agregação determinística e ID canônico. `BillingCycleReportsScreen` existe com estrutura UI.
Phase 7 completa e formaliza essa fundação.

**Objetivo:** Transformar os snapshots financeiros imutáveis em evidências acionáveis —
relatórios de conformidade, exports para controladoria e auditoria, dashboard executivo.

#### [ ] 7.1 — Design Specification
**Artefato:** `docs/architecture/11_evidence_audit_exports_design.md`

Cobrir obrigatoriamente:
- **Billing Cycle Report:** completar implementação da `BillingCycleReportsScreen` (CSV export, período customizável, filtro por contrato)
- **Monthly Compliance Report:** aggregation pipeline usando `pg_cron` (job mensal por org/contrato)
- **PDF export:** layout de relatório para auditoria (cabeçalho, sumário executivo, detalhamento por SET)
- **Executive Dashboard:** KPIs agregados — taxa de compliance, receita protegida/em risco/perdida por período
- **Provenance chain:** relatório exportado referencia `snapshotIds` e `ledgerEntryIds` — rastreável ao evento original
- **Imutabilidade:** relatórios gerados são read-only — qualquer regeneração cria nova versão, nunca sobrescreve
- **Tenant scoping:** jobs `pg_cron` processam 1 `organization_id` por vez — sem cross-tenant analytics

#### [ ] 7.2 — Council Review
Validar antes de implementar:
- Jobs de aggregation operam sobre snapshots imutáveis, não sobre o ledger bruto
- Export CSV/PDF derivado dos snapshots do período — replay produz o mesmo arquivo
- `pg_cron` jobs incluem `organization_id` explícito — sem scans globais
- Relatório exportado não pode ser alterado após gerado

#### [ ] 7.3 — Implementation
- **SQL:** `monthly_compliance_reports` table, `pg_cron` jobs de fechamento mensal, indexes
- **Domain:** `ComplianceReport` entity (se necessário além de `BillingCycleReport`)
- **Application:** `ReportGenerationService`, `CsvExportService`, `PdfExportService`
- **Infrastructure:** Repositórios para reports, integração `pg_cron`
- **Presentation:**
  - Completar `BillingCycleReportsScreen` (export CSV funcional, seleção de período)
  - Tela de relatórios mensais de compliance
  - Export PDF para auditoria
  - Executive Dashboard com KPIs por período

#### [ ] 7.4 — Validation

**Cenários automatizados:**
- Cenário 7.1: Relatório mensal produz totais idênticos à soma dos snapshots diários do período
- Cenário 7.2: Export CSV de Org A não contém nenhum dado de Org B
- Cenário 7.3: Regenerar relatório do mesmo período produz arquivo matematicamente idêntico (determinismo)
- Cenário 7.4: Relatório exportado contém `snapshotIds` rastreáveis ao ledger original
- Cenário 7.5: Job `pg_cron` não reprocessa snapshots já fechados

**⚠️ Testes Manuais Obrigatórios (verificação visual de outputs):**
> Downloads de arquivo e rendering de PDF/CSV não podem ser validados por `flutter test`.

- [ ] **Export CSV:** clicar em "Exportar CSV" → baixar arquivo → abrir em planilha → verificar que colunas, valores monetários (em reais, não centavos) e encoding (UTF-8 com BOM para Excel) estão corretos
- [ ] **Export PDF:** gerar relatório de auditoria → abrir PDF → verificar cabeçalho da org, período, totais financeiros e referência ao `snapshotId`
- [ ] **Determinismo visual:** gerar o mesmo relatório duas vezes → comparar arquivos — devem ser byte-a-byte idênticos (exceto timestamp de geração se houver)
- [ ] **Executive Dashboard:** navegar pelo dashboard com dados reais de ≥ 1 mês → verificar que KPIs de receita protegida/em risco/perdida batem com a soma dos snapshots no Supabase
- [ ] **Rastreabilidade:** clicar em um valor do relatório → verificar que o link/referência leva ao ledger entry original

- **Compliance Report:** `docs/governance/compliance/phase7_compliance_report.md`

---

### [ ] Phase 8 — Operational Hardening

**Por que depois de Phase 7:** O hardening operacional prepara o produto para receber tráfego real.
Executá-lo antes de ter todas as features seria otimizar prematuramente —
testar performance e CI/CD de algo incompleto é trabalho dobrado.

**Objetivo:** Transformar o projeto de "dev pessoal" em infraestrutura operável.
Esta phase não adiciona features — garante que as existentes sejam confiáveis, monitoráveis,
seguras e recuperáveis em produção.

#### [ ] 8.1 — CI/CD Pipeline
**Artefatos:** `.github/workflows/ci.yml` · `.github/workflows/deploy.yml`

```
Pull Request →
  flutter analyze (zero erros)
  flutter test --no-pub (todos passing)
  flutter build web

Push main →
  todos os passos acima
  deploy automático → Staging (PactaFlow-staging no Supabase)

Tag vX.Y.Z →
  todos acima
  deploy → Production (aprovação manual obrigatória)
```

#### [ ] 8.2 — Separação de Ambientes
- 3 projetos Supabase: `PactaFlow-dev` · `PactaFlow-staging` · `PactaFlow-prod`
- Processo de promoção de migrations: dev → staging → prod (nunca pular)
- `--dart-define` injetados por ambiente no CI (sem `.env` em pipeline)
- Dados de teste **nunca** chegam em prod

#### [ ] 8.3 — Observabilidade
- Error tracking: Sentry (Flutter SDK + Supabase Edge Functions)
- Logging estruturado: JSON com `organization_id`, `user_id`, `correlation_id` em cada entrada
- Substituir todos os `print()` por logger estruturado (detectáveis via `avoid_print` já ativo)
- Alertas: notificação se ledger write > 2s ou taxa de erro > 1%

#### [ ] 8.4 — Segurança (Hardening Final)
- Remover políticas `Public Read` das tabelas críticas no RLS
- Adicionar `mutated_by_user_id` + `mutated_reason` nas tabelas mutáveis (`execution_states`, `operational_alerts`)
- **Type-safety pass:** habilitar `strict-casts: true` e corrigir ~80 erros de `dynamic` nos repositórios Postgres
- Field-level masking para PII (nome de motorista, placa onde exposto em queries de relatório)

**⚠️ Testes Manuais de Segurança (penetration test):**
> Estes testes são executados manualmente com DevTools do browser e ferramentas como Postman/curl.
> Não são automatizáveis dentro do `flutter test`.

- [ ] **JWT tampering:** modificar o `organization_id` no JWT decodificado (via DevTools ou jwt.io) → confirmar que Supabase RLS rejeita a query e retorna 0 rows (não erro 403, mas isolamento silencioso)
- [ ] **Cross-tenant read:** autenticado como usuário de Org A, fazer query REST direta na API Supabase para tabela `execution_states` sem filtro → confirmar que retorna apenas dados de Org A
- [ ] **RLS bypass attempt:** tentar acessar tabelas via Supabase REST API com `anon key` sem estar autenticado → confirmar que retorna 0 rows (RLS block)
- [ ] **Inspeção de rede:** abrir DevTools → aba Network → verificar que nenhuma chamada à API Supabase expõe `service_role key` ou dados de outras orgs no payload de resposta
- [ ] **`strict-casts` habilitado:** após corrigir os ~80 erros de `dynamic`, rodar `flutter analyze` e confirmar 0 erros com `strict-casts: true`

#### [ ] 8.5 — Performance & Escala
- Load test: 1.000 veículos simultâneos com telemetria contínua
- Benchmark `ContractualEvaluationEngine` (meta: < 100ms por vehicle state)
- Revisão de índices com base nas queries reais de staging
- Avaliar read replicas para queries de relatório (não competir com writes do ledger)

#### [ ] 8.6 — Disaster Recovery
- Documentar estratégia de backup (Supabase PITR — Point-in-Time Recovery)
- Runbook de restore com tempo estimado e responsável pela autorização
- Definir RPO/RTO para dados financeiros (meta: RPO ≤ 1h · RTO ≤ 4h)
- Testar restore em ambiente isolado ao menos 1× antes do lançamento

---

### [ ] Trilha D — Lançamento

**Por que "Trilha" e não "Phase":** Esta etapa não é técnica e não segue o ciclo
`Design → Review → Implementation → Validation`. É o conjunto de ações comerciais,
legais e de go-to-market necessárias para transformar o produto técnico em produto de mercado.

**Pré-requisito:** Phases 5, 6, 7 e 8 concluídas.

#### [ ] D1 — Documentação de Produto
- Landing page com proposta de valor (ledger imutável vs. TMS tradicionais)
- Guia de onboarding para novos clientes (do signup ao primeiro SLA auditado)
- Guia de integração de telemetria (como conectar GPS/IoT existente ao PactaFlow)
- Changelog público com versionamento semântico

#### [ ] D2 — Modelo Comercial
- Definir pricing: por veículo/mês · por organização · por execução auditada
- Contrato de prestação SaaS (termos de uso + SLA do próprio PactaFlow)
- Política de privacidade LGPD (obrigatório — plataforma processa dados de motoristas e operadores)
- Processo de cobrança: Stripe ou similar integrado ao ciclo de onboarding

#### [ ] D3 — Piloto Beta Controlado
> **Este é o maior teste manual do produto** — realizado por usuários reais, não pelo desenvolvedor.

- Selecionar 2–3 clientes reais com contratos de transporte ativos
- Monitoramento intensivo durante o piloto (Sentry + contato direto)
- Coleta estruturada de feedback a cada 2 semanas
- **Critério de saída do beta:** zero incidentes críticos em 30 dias corridos
- Ajustes de produto incorporados antes do lançamento

---

## Visão Geral de Execução

```
─────────────────────────────────────────────────────
[x] Sprint 5.12 Phase D — Refinement & Security Hotfixes (INV-2 · INV-3 · INV-6)
     [x] Step 1 UI Rebuild Fix
     [x] Step 2 UTC Standardization
     [x] Step 3 Stale Schema Doc
     [x] Step 4 SQL Migration (Tenant Isolation)
     [x] Step 5 Infra Org Isolation
─────────────────────────────────────────────────────
[x] 5.12 Final Operational Validation (Final Sign-off) ✅
─────────────────────────────────────────────────────
[ ] Sprint 5.13 — Post-Validation Hardening (Blocos 2, 3 e 4) [BLOCO 2 DONE]
     ⚠️  Bloco 5 adicionado: 3 bugs encontrados em testes manuais (5.1 BLOQUEANTE)
     [x] Bloco 2 (2.1–2.4)
     [ ] Bloco 5: 5.1 RLS Fix (bloqueante) · [DONE] 5.2 Geofence callback · [DONE] 5.3 JIT stale
─────────────────────────────────────────────────────
[  ] Phase 6  Administration & Tenant Self-Service
        ⚠️  Phase 6 introduz `Contractor` aggregate → migrar `contractor_label TEXT` para FK real
[  ] Phase 7  Evidence & Audit Exports
[  ] Phase 8  Operational Hardening
       `PostgresSlaTemplateRepository` — strict types aplicados (Sprint 5.11)
[  ] Trilha D Lançamento
```

---

## Próximo passo

**Sprint 5.13 Bloco 2 completo (2.1–2.4). Testes manuais identificaram 3 bugs — Bloco 5 adicionado como pré-requisito para Blocos 3 e 4.**

### Sequência imediata

```
1. [ ] Sprint 5.13 Bloco 5 — Regression Fixes (BLOQUEANTE: 5.1 primeiro)
   1a. [ ] PO confirma nome da RLS policy atual via Supabase Dashboard
   1b. [ ] SQL 5.1 executado e confirmado
   1c. [x] Bugs 5.2 e 5.3 implementados (sem SQL) [DONE]
2. [ ] Sprint 5.13 Blocos 3 e 4
3. [ ] Phase 6                — Administration & Tenant Self-Service
```

### Atenção: itens que PODEM afetar trabalho já concluído

| Risco | Fase futura | Mitigação já documentada |
|-------|-------------|--------------------------|
| `Contractor` aggregate (Phase 6) pode exigir migrar `contractor_label TEXT` → FK | Phase 6.3 | Documentado como migração planejada; `contractor_label` é tag temporária por design |
| B1 Localization pt-BR altera widgets de calendário usados no Wizard | ~~B1 remanescente~~ | ✅ Resolvido — localization já configurada, smoke test pode prosseguir |
| `PostgresSlaTemplateRepository` usava `dynamic` | ~~Phase 8.4~~ | ✅ Corrigido em Sprint 5.11 — `List<Map<String,dynamic>>` strict |
| `supabase_smoke_test.dart:2.2` falha por falta de inicialização de timezone em teste puro | ~~Débito técnico~~ | ✅ Corrigido em Sprint 5.11 — `setUpAll` incondicional chama `BrazilTime.ensureInitialized()` |
