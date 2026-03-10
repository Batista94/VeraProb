# BusFlow — Roadmap Estratégico

## Contexto do Projeto

**Status atual:** Projeto pessoal em ambiente de desenvolvimento (dev local).
**Objetivo:** Produto de mercado B2B competindo com soluções TMS existentes.
**Stack:** Flutter Web (OCC) · Supabase (PostgreSQL 15+, RLS, Realtime, PostGIS) · Riverpod

**Diferencial central:** Plataforma de inteligência operacional orientada a eventos que
transforma telemetria GPS bruta em verdade contratual verificável — ledger imutável +
avaliação determinística de SLA + impacto financeiro auditável por ciclo de cobrança.

---

## Regra de Governança (nunca pular)

Cada fase segue obrigatoriamente o ciclo definido no `.cursorrules`:

```
Design Spec → Council Review → Implementation → Validation → Compliance Report
```

- Nenhuma linha de código de feature é escrita antes do Design Spec estar aprovado
- Nenhuma fase é considerada concluída sem Compliance Report gerado
- Toda decisão arquitetural significativa gera um ADR em `docs/governance/adr/`

### Política de Testes Manuais

Testes automatizados (`flutter test`) cobrem lógica de domínio, projeções e fluxos in-memory.
**Não cobrem:** rendering de UI no browser, fluxos multi-tela, realtime WebSocket, exports PDF/CSV,
RBAC com sessão real, convites por email, ou qualquer comportamento dependente de Supabase ativo.

Testes manuais são **obrigatórios** antes de emitir o Compliance Report das seguintes fases:

| Fase | Por quê é obrigatório |
|------|-----------------------|
| **Phase 5.4** | Primeiro fluxo completo do operador via UI — não existia antes |
| **Phase 6.4** | RBAC com sessão real, convite por email — não automatizáveis por natureza |
| **Phase 7.4** | PDF/CSV renderizados no browser — requerem verificação visual |
| **Phase 8** | Penetration test, inspeção de DevTools, carga real |
| **Trilha D.D3** | Beta com usuários reais — validação de produto, não só técnica |

Fases anteriores (0–4) não têm testes manuais pendentes pois não entregaram fluxo completo de usuário.
Exceção: se qualquer UI de Phase 3 ou 4 (`InvestigationModal`, `ContractualAlertsPanel`) nunca tiver
sido testada manualmente em Supabase real, incluir no smoke test de Phase 5.

---

### Invariantes não-negociáveis (`.cursorrules`)
- **Ledger imutável:** sem UPDATE, sem DELETE — eventos são fatos históricos
- **Precisão financeira:** Money em centavos inteiros (BIGINT), nunca double/float
- **Tempo:** UTC no domínio e banco; conversão de fuso somente na UI
- **Soberania do domínio:** camada de domínio é Dart puro — sem Flutter, sem Supabase
- **Engine único:** só o `ContractualEvaluationEngine` calcula penalidades, transiciona estados, gera impacto financeiro
- **OCC read-only:** a console operacional nunca chama repositórios de escrita
- **Multi-tenancy:** todo evento e toda query carrega `organization_id` — sem exceções
- **Idempotência:** replay de eventos produz exatamente o mesmo estado

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---------|--------|
| Testes | 229 passing · 9 skipped (E2E sem credenciais) · 0 falhas |
| Análise estática | 0 erros · 71 infos (`prefer_const` — baixa prioridade) |
| Precisão financeira | `Money` (centavos BIGINT) em todo o stack — invariante enforced ✅ |
| CI/CD | Não existe (Phase 8) |
| Ambientes | Dev local único. Sem staging, sem prod. |
| `strict-casts` | Desabilitado — ~80 issues de `dynamic` nos repos Postgres (Phase 8) |
| Banco de dev | **Precisa de reset** antes de aplicar migration de Phase 5 |

---

## Fases Concluídas

### [x] Phase 0 — Core Stabilization
- [x] Corrigido `UnimplementedError` síncrono no `PostgresAuditService`
- [x] Resolvido `ClientException` (CORS) em queries do ledger
- [x] Corrigido bug de consistência realtime (veículos no sidebar mas ausentes no `FleetMap`)
- [x] Implementado `ErrorBoundary` global para prevenir crashes de nível raiz

### [x] Phase 1 — Multi-Tenancy & Auth Foundation
- [x] Arquitetura multi-tenant definida (RLS + boundaries)
- [x] Migration: tabela `organizations`, HASH partitioning no ledger, políticas RLS, Custom JWT hook
- [x] `organizationId` como coluna de isolamento em todas as entidades e DTOs
- [x] Supabase Auth substituindo PIN estático de 4 dígitos
- [x] `AuthService` conectado a perfis de usuário via JWT challenge
- [x] **Validation:** Cenários de isolamento dual-org executados e documentados

### [x] Phase 2 — Contract Rules & Configurable Determinism
- [x] **Design:** `ContractualRule` entity e modelo de versionamento de regras
- [x] **Design:** Contexto de avaliação temporal (Rule Replay)
- [x] **Council Review:** Deterministic safety e isolamento validados
- [x] **Implementation:** Schema Postgres (`contract_rule_sets`, `contract_rule_versions`)
- [x] **Implementation:** Domain models (`ContractualRule`, `RuleSnapshot`)
- [x] **Implementation:** `PlanDeclaration` e repositórios atualizados para snapshots
- [x] **Implementation:** `ContractualEvaluationEngine` com invocação dinâmica de regras
- [x] **Validation:** Rule Replay Integrity & cenários de simulação

### [x] Phase 3 — Explainability & Investigation
- [x] **Design:** `EvaluationTrace`, `EvaluationDecision`, `EngineEvaluationResult`
- [x] **Council Review:** Schema de trace, integração OCC, causal linkage validados
- [x] **Infrastructure:** Migration `contractual_evaluation_traces` (append-only, RLS)
- [x] **Application:** Engine refatorado para emitir traces determinísticos
- [x] **Persistence:** Repos Postgres e InMemory com linkage causal ao ledger
- [x] **Presentation:** OCC `InvestigationModal` com timeline, decision cards, evidence
- [x] **Validation:** 8 cenários de compliance — todos passando

### [x] Phase 4 — Operational Alerts
- [x] **Design:** Alert derivation, lifecycle, OCC visualization, storage
- [x] **Council Review:** Alert model, isolamento de tenant, idempotência validados
- [x] **Domain:** `OperationalAlert` entity e `OperationalAlertRepository` interface
- [x] **Application:** `AlertDerivationService` e `AlertService` com lifecycle enforcement
- [x] **Infrastructure:** Migration com constraint UNIQUE de idempotência, RLS, indexes
- [x] **Infrastructure:** Repos Postgres e InMemory
- [x] **Engine:** Alert derivation integrada ao pipeline `_commitEvaluationResults`
- [x] **Presentation:** OCC `ContractualAlertsPanel` com severity sort, investigate, acknowledge
- [x] **Validation:** 10 cenários de compliance — todos passando

### [x] Trilha A — Correções Críticas de Débito Técnico
> Executada após Phase 4 antes de avançar em features.
> Pré-requisito para qualquer nova fase ter confiança de base.

#### [x] A1 — Suite de Testes (229 passing, 0 falhas)
- [x] `enums_test.dart` — labels desatualizados corrigidos no teste (produção estava correta)
- [x] `sla_financial_impact_screen_test.dart` — `currentOrganizationIdProvider` era `null`; teste não simulava sessão autenticada. Corrigido sobrescrevendo provider no `ProviderScope`
- [x] `contractual_evaluation_subscriber_test.dart` — execution state não seedado antes do subscriber. Corrigido adicionando `repo.save(makeExecState())` no teste específico
- [x] `contract_rules_validation_test.dart` (Scenario 2.2) — queries usavam `'org-1'` mas estados estavam em `'org-a'`/`'org-b'`. Engine agora chamado com cada org separadamente
- [x] `realtime_data_provider_test.dart` — assertion síncrona em stream assíncrono. Corrigido com `async` + `await Future.delayed(Duration.zero)`
- [x] `sla_audit_e2e_postgres_test.dart` — `setUpAll` sem credenciais lançava exceção como falha. Substituído por skip condicional explícito

#### [x] A2 — Análise Estática
- [x] `analysis_options.yaml` com lints ativos: `avoid_print`, `unawaited_futures`, `prefer_const_constructors`, `always_declare_return_types`, `exhaustive_cases`, `missing_return: error`
- [x] `strict-casts` documentado como intencionalmente desabilitado (endereçado na Phase 8)

#### [x] A3 — Gestão de Segredos
- [x] `.env` confirmado como nunca versionado
- [x] `.env.example` criado com instruções para dev e CI/CD
- [x] `SUPABASE_KEY` confirmada como chave `anon` (não `service_role`)

#### [x] A4 — Precisão Financeira (violação pré-Phase 5)
> Detectada durante Council Review de Phase 5 — bloqueante antes de qualquer nova feature.

- [x] `contractualValue: double` → `Money` em todo o stack (domínio, aplicação, infraestrutura, apresentação)
- [x] `ContractualServiceExecution` e `ContractualExecutionState` — campo e assinaturas atualizados
- [x] `DeclareContractualPlanHandler` — converte `double → Money` no boundary (input DTO continua `double`)
- [x] `SlaExecutionItemView`, `SlaExecutionSummary` — campos `Money`; UI usa `.toDouble()` para `NumberFormat`
- [x] `SlaExecutionQueryServiceInMemory` e `PostgresSlaExecutionQueryService` — acumulação com operadores `Money`
- [x] `ContractualFinancialSnapshotGenerator` — removido `Money.fromDouble()` desnecessário
- [x] Repositórios Postgres — escrita `.cents`, leitura `Money(int)`, coluna renomeada `contractual_value_cents`
- [x] Migration `20260309000000_financial_precision_cents.sql` — `DOUBLE PRECISION → BIGINT`, backfill, DROP coluna antiga
- [x] 15 arquivos de teste atualizados — 229 passing · 0 falhas

---

## Fases Pendentes

> Ordem de execução é obrigatória — fases não podem ser puladas (`.cursorrules`).

---

### [~] Phase 5 — Contract & Plan Lifecycle Management

**⟵ EM ANDAMENTO — Design Spec aprovado, implementação próxima**

**Por que agora:** O motor de avaliação (Phases 0–4) está completo e determinístico.
Mas atualmente **não existe nenhuma UI para um operador criar um contrato ou declarar um plano** —
isso só é possível via Supabase dashboard ou inserção direta por código.
A plataforma tem motor, mas não tem volante. Phase 5 constrói o volante.

**Objetivo:** Interface completa para o ciclo de vida contratual — da criação de um contrato
até o encerramento auditável do ciclo. Esta é a jornada primária do operador no produto.

#### [x] 5.1 — Design Specification
**Artefato:** `docs/architecture/09_contract_plan_lifecycle_design.md` ✅
- [x] `Contract` aggregate: `draft → active → closed` (renovação adiada para Phase 6)
- [x] `validFromUtc` / `validUntilUtc` como campos obrigatórios na criação
- [x] `DeclareContractualPlanHandler` modificado para validar `Contract` antes de criar plano
- [x] `originalFileHash` gerado como SHA-256 do JSON do command para planos criados via UI
- [x] `CloseContractCommand` implementado no domínio; **botão de UI adiado para Phase 6** (requer RBAC)
- [x] Encerrar com SETs ativos: permitido com modal de confirmação na UI
- [x] Listagem com filtros por status e vigência; formulário criar + declarar plano; tela de detalhe
- [x] Banco de dev: reset completo antes de aplicar migration (sem dados a preservar)

#### [x] 5.2 — Council Review ✅
- [x] Plano via UI passa pelo mesmo `DeclareContractualPlanHandler` — sem bypass do domínio
- [x] UI nunca escreve diretamente em repositórios — usa commands
- [x] Transições de status controladas pelo domínio (`Contract.assertCanReceivePlan()`)
- [x] `organization_id` derivado do JWT, nunca de input do formulário
- [x] `contractId` referencia `Contract` real — validado pelo handler (DomainException se não existir)
- [x] Todas as 5 decisões de produto registradas e incorporadas ao spec

#### [ ] 5.3 — Implementation  ← **PRÓXIMO PASSO**
- **Domain:** `Contract` aggregate + `ContractStatus` enum + `ContractRepository` interface
  + events: `ContractCreatedEvent`, `ContractActivatedEvent`, `ContractClosedEvent`
- **Application:** `CreateContractHandler`, `CloseContractHandler`
  + `DeclareContractualPlanHandler` modificado (valida Contract + ativa automaticamente)
  + `ContractQueryService` + `ContractSummaryView` + `ContractDetailView`
- **Infrastructure:** migration SQL (`contracts` table + FK em `plan_declarations` + reset dev)
  + `InMemoryContractRepository` + `PostgresContractRepository`
  + `ContractQueryServiceInMemory` + `ContractQueryServicePostgres`
- **Presentation:**
  - `ContractsScreen` — listagem com filtros por status e vigência
  - `CreateContractForm` — com `validFromUtc` / `validUntilUtc`
  - `DeclareContractPlanForm` — SETs configuráveis (viagens programadas)
  - `ContractDetailScreen` — abas: execuções, histórico de planos, financeiro

#### [ ] 5.4 — Validation

**Cenários automatizados:**
- Cenário 5.1: Plano criado via UI gera ledger entry `PLAN_DECLARED` — mesmo comportamento da API
- Cenário 5.2: Plano publicado não pode ser editado — apenas nova versão aceita
- Cenário 5.3: Operador de Org A não vê contratos de Org B na listagem
- Cenário 5.4: Contrato encerrado não aceita novos planos

**⚠️ Testes Manuais Obrigatórios (Supabase dev ativo):**
> Este é o primeiro momento em que existe um fluxo completo de usuário na UI.
> Executar com Supabase real antes de emitir o Compliance Report.

- [ ] **Smoke test de UI existente (fases 3 e 4):** Abrir `InvestigationModal` e `ContractualAlertsPanel` no browser — verificar que renderizam sem erros com dados reais
- [ ] **Criar contrato** via formulário da OCC → confirmar que aparece na listagem com status correto
- [ ] **Declarar plano** com ≥ 2 SETs → confirmar que ledger entry `PLAN_DECLARED` é gerada no Supabase
- [ ] **Plano publicado não editável:** tentar editar plano existente → verificar que UI bloqueia ou retorna erro de domínio correto
- [ ] **Isolamento de tenant:** logar como usuário de Org A → confirmar que nenhum contrato de Org B aparece na listagem
- [ ] **Pipeline de avaliação:** após plano declarado, simular telemetria via Realtime → confirmar que execução muda de `pending` → `executed` na UI sem refresh manual
- [ ] **Contrato encerrado (via teste automatizado/API):** confirmar que `CloseContractCommand` funciona no domínio e que declarar novo plano retorna `DomainException` — botão de UI vem na Phase 6

- **Compliance Report:** `docs/governance/compliance/phase5_compliance_report.md`

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
  deploy automático → Staging (busflow-staging no Supabase)

Tag vX.Y.Z →
  todos acima
  deploy → Production (aprovação manual obrigatória)
```

#### [ ] 8.2 — Separação de Ambientes
- 3 projetos Supabase: `busflow-dev` · `busflow-staging` · `busflow-prod`
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
- Guia de integração de telemetria (como conectar GPS/IoT existente ao BusFlow)
- Changelog público com versionamento semântico

#### [ ] D2 — Modelo Comercial
- Definir pricing: por veículo/mês · por organização · por execução auditada
- Contrato de prestação SaaS (termos de uso + SLA do próprio BusFlow)
- Política de privacidade LGPD (obrigatório — plataforma processa dados de motoristas e operadores)
- Processo de cobrança: Stripe ou similar integrado ao ciclo de onboarding

#### [ ] D3 — Piloto Beta Controlado
> **Este é o maior teste manual do produto** — realizado por usuários reais, não pelo desenvolvedor.

- Selecionar 2–3 clientes reais com contratos de transporte ativos
- Monitoramento intensivo durante o piloto (Sentry + contato direto)
- Coleta estruturada de feedback a cada 2 semanas
- **Critério de saída do beta:** zero incidentes críticos em 30 dias corridos
- Ajustes de produto incorporados antes do lançamento geral

**O que observar durante o beta (testes de aceitação do usuário):**
- [ ] Operador consegue criar contrato e declarar plano **sem auxílio do desenvolvedor**
- [ ] Alertas operacionais aparecem no tempo esperado após telemetria processada
- [ ] Relatório exportado é aceito pelo cliente final do operador (contratante do transporte)
- [ ] Nenhum dado de um cliente beta vaza para outro (verificar via Sentry + logs)
- [ ] Performance aceitável com volume real de veículos (sem Page freezes, sem timeouts visíveis)

---

## Visão Geral de Execução

```
[✅] Phase 0  Core Stabilization
[✅] Phase 1  Multi-Tenancy & Auth Foundation
[✅] Phase 2  Contract Rules & Configurable Determinism
[✅] Phase 3  Explainability & Investigation
[✅] Phase 4  Operational Alerts
[✅] Trilha A Correções Críticas de Débito Técnico (A1 testes · A2 lints · A3 segredos · A4 precisão financeira)
─────────────────────────────────────────────────────
[~] Phase 5  Contract & Plan Lifecycle Management    ← EM ANDAMENTO
     ✅ 5.1 Design Spec   ✅ 5.2 Council Review
     ⏳ 5.3 Implementation  ·  5.4 Validation
[  ] Phase 6  Administration & Tenant Self-Service
[  ] Phase 7  Evidence & Audit Exports
[  ] Phase 8  Operational Hardening
[  ] Trilha D Lançamento
```

---

## Próximo passo

**Phase 5.3 — Implementation.**

Ordem obrigatória:
1. Domínio: `Contract` aggregate + `ContractStatus` + eventos de domínio
2. Aplicação: handlers + query service
3. Infraestrutura: migration SQL (reset dev primeiro) + repositórios
4. Apresentação: telas de listagem, criação, declaração de plano e detalhe
5. Testes e Phase 5.4 Validation
