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
| **Phase 5.10** | Primeiro fluxo completo do operador via UI com B2B Refactoring (zonas, turnos, SLA) — inclui cenários originais da 5.4 |
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
  - *Exceção documentada (ADR Phase 5.7):* `ShiftPattern` armazena `arrivalTimeLocal + timezone` (IANA string) porque regras de recorrência não podem ser expressas em UTC absoluto. A conversão local → UTC ocorre no `ShiftProjectionService` no momento da projeção, não no domínio.
- **Soberania do domínio:** camada de domínio é Dart puro — sem Flutter, sem Supabase
- **Engine único:** só o `ContractualEvaluationEngine` calcula penalidades, transiciona estados, gera impacto financeiro. O `ShiftProjectionService` (Phase 5.7) é um application service separado responsável pela geração de SETs — não é um segundo engine de avaliação.
- **OCC read-only:** a console operacional nunca chama repositórios de escrita
- **Multi-tenancy:** todo evento e toda query carrega `organization_id` — sem exceções
- **Idempotência:** replay de eventos produz exatamente o mesmo estado. SETs projetados por `ShiftProjectionService` são protegidos por unique constraint `(plan_declaration_id, shift_pattern_index, operational_date)` no banco.

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---------|--------|
| Testes | 340 passing · 16 skipped · 0 falhas ✅ |
| Análise estática | 0 erros · 67 infos (`prefer_const` — baixa prioridade) |
| Precisão financeira | `Money` (centavos BIGINT) em todo o stack — invariante enforced ✅ |
| CI/CD | Não existe (Phase 8) |
| Ambientes | Dev local único. Sem staging, sem prod. |
| `strict-casts` | Desabilitado — ~80 issues de `dynamic` nos repos Postgres (Phase 8) |
| Sprint 5.11 | **CONCLUÍDA** — Fases A-I implementadas (Wizard refatorado, Clona Contrato, Templates SLA, Contractor Label). |
| Banco de dev | Todas as migrations aplicadas — `20260311000000` · `20260311000002` · `20260311000003` · `20260312000001` · `20260312000002` · `20260312000003` ✅ |

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

### [x] Phase 5 — Contract & Plan Lifecycle Management (B2B Refactoring)

**✅ CONCLUÍDA — Hardened by QA & Security Persona**

**Objetivo original (5.1–5.3):** Interface completa para o ciclo de vida contratual.
Implementação baseline concluída e preservada como referência de domínio.

**Objetivo revisado (B2B Refactoring):** Domínio refatorado para falar a linguagem do
fretamento corporativo B2B. O operador configura regras de negócio — não coordenadas GPS
e timestamps manuais. Três novos conceitos de domínio:
- `OperationalZone` — zona geofenceada com nome comercial ("Garagem Central", "Portaria Sul")
- `ShiftPattern` — padrão de recorrência ("Seg–Sex, chegada às 07:00, fuso America/Sao_Paulo")
- `SLAPenalties` — ofensores de margem: no-show, atraso por minuto, downgrade de frota

---

#### [x] 5.1 — Design Specification (baseline)
**Artefato:** `docs/architecture/09_contract_plan_lifecycle_design.md` ✅
- [x] `Contract` aggregate: `draft → active → closed` (renovação adiada para Phase 6)
- [x] `validFromUtc` / `validUntilUtc` como campos obrigatórios na criação
- [x] `DeclareContractualPlanHandler` modificado para validar `Contract` antes de criar plano
- [x] `originalFileHash` gerado como SHA-256 do JSON do command para planos criados via UI
- [x] `CloseContractCommand` implementado no domínio; botão de UI adiado para Phase 6 (requer RBAC)
- [x] Encerrar com SETs ativos: permitido com modal de confirmação na UI

#### [x] 5.2 — Council Review (baseline) ✅
- [x] Plano via UI passa pelo mesmo `DeclareContractualPlanHandler` — sem bypass do domínio
- [x] UI nunca escreve diretamente em repositórios — usa commands
- [x] Transições de status controladas pelo domínio (`Contract.assertCanReceivePlan()`)
- [x] `organization_id` derivado do JWT, nunca de input do formulário
- [x] `contractId` referencia `Contract` real — validado pelo handler (DomainException se não existir)

#### [x] 5.3 — Implementation (baseline — supersedida pelo B2B Refactoring) ✅
> Artefatos preservados como referência. Serão refatorados nas fases 5.7–5.9.
- **Domain:** `Contract` aggregate + `ContractStatus` + `ContractRepository`
  + events: `ContractCreatedEvent`, `ContractActivatedEvent`, `ContractClosedEvent`
- **Application:** `CreateContractHandler`, `CloseContractHandler`
  + `DeclareContractualPlanHandler` modificado + `ContractQueryService`
- **Infrastructure:** migration SQL (`contracts` table + FK em `plan_declarations`)
  + `InMemoryContractRepository` + `PostgresContractRepository`
- **Presentation:** `ContractsScreen` · `CreateContractForm` · `DeclareContractPlanForm` · `ContractDetailScreen`

#### [⏸] 5.4 — Validation (suspensa)
> **Suspensa.** Substituída pela Phase 5.10 (Validation Consolidada) que cobre os cenários
> originais desta fase mais os novos cenários do B2B Refactoring.

---

#### B2B Contract Refactoring — Council Review 2026-03-10

**Design Spec aprovado:** `OperationalZone` + `ShiftPattern` + `SLAPenalties`.
Council Review conduzido com red teaming cruzado (Architect · Senior Eng · QA/Security · UX/Ops).
**4 BLOCKERs resolvidos · Opção A concluída · Implementação liberada:**

| # | BLOCKER | Decisão | Status |
|---|---------|---------|--------|
| B1 | Engine único | `ShiftProjectionService` Dart acionado pelo handler (projeta 30 dias) + boot check (`ensureProjected` no login) | ✅ Resolvido |
| B2 | Imutabilidade | Lat/lng/radius snapshotados no `ContractualServiceExecution` no momento da projeção; `zoneId` apenas para auditoria | ✅ Resolvido |
| B3 | Precisão financeira | `SLAPenalties { double noShowPenaltyMultiplier · int delayToleranceMinutes · Money delayPenaltyPerMinute · Money downgradePenaltyFlat }` | ✅ Resolvido |
| B4 | Observabilidade | Gap permanente + `OperationalAlert` tipo `PROJECTION_GAP` / severity `CRITICAL`. Sem retroatividade. | ✅ Resolvido |

#### [x] 5.5 — Blocker Resolution ✅
- [x] B1: `ShiftProjectionService` como application service Dart — handler eager (30 dias) + boot check
- [x] B2: Coordenadas snapshotadas no SET projetado — `zoneId` como auditoria apenas
- [x] B3: `SLAPenalties` com `Money delayPenaltyPerMinute` + `Money downgradePenaltyFlat` + `double noShowPenaltyMultiplier`
- [x] B4: Gap permanente + `PROJECTION_GAP` CRITICAL — sem backfill retroativo

#### [x] 5.6 — Database Foundation ✅
> **Migration principal:** `supabase/migrations/20260311000000_b2b_refactoring_foundation.sql`
> **Migration complementar (Sprint 5.10 Realignment):** `supabase/migrations/20260311000002_operational_zone_business_fields.sql`
> - Torna `latitude · longitude · radius_meters` nullable (`GeofenceConfiguration` opcional)
> - Adiciona `type TEXT NOT NULL DEFAULT 'garagem'` e `address TEXT`
> **Migration adicional (Sprint 5.10 Fase 2):** `supabase/migrations/20260311000003_operational_zones_add_created_at.sql`
> - Adiciona `created_at TIMESTAMPTZ NOT NULL DEFAULT now()` à tabela `operational_zones`
> - Corrige erro `ERROR: 42703: column "created_at" does not exist` ao criar zonas via UI
> **⚠️ Ação do PO:** executar **as três** migrations no Supabase antes de iniciar Phase 5.10 (testes manuais).
- `operational_zones` table com RLS (`USING` + `WITH CHECK`) e `ON DELETE RESTRICT` nas FKs de `shift_patterns`
- `ShiftPattern` como payload JSONB em `plan_declarations` (componente do aggregate — sem tabela independente)
- Unique constraint de idempotência: `(plan_declaration_id, shift_pattern_index, operational_date)` em `contractual_service_executions`
- Colunas adicionais em `contractual_service_executions`: `origin_zone_id · destination_zone_id · delay_tolerance_minutes · operational_date · shift_pattern_index`
- `delay_penalty_per_minute_cents BIGINT · downgrade_penalty_flat_cents BIGINT` em `contractual_service_executions` (snapshot de `SLAPenalties`)

#### [x] 5.7 — Domain Refactoring
- [x] `OperationalZone` entity (org-scoped): `name · type (ZoneType enum) · address? · geofence (GeofenceConfiguration?)`
  - `GeofenceConfiguration` é VO separado — garante que lat/lng/radius são presentes juntos ou ausentes juntos. Nunca defaulta para 0.0/0.0 (Gulf of Guinea).
  - Geofence é **opcional na criação** (UI exibe em ExpansionTile "Avançado") mas **obrigatório na projeção** — `ShiftProjectionService` lança `DomainException` se zona referenciada no turno não tiver geofence.
  - `ZoneType`: `garagem | cliente | apoio`
- [x] `ShiftPattern` value object (componente de `PlanDeclaration`): `daysOfWeek · arrivalTimeLocal · departureTimeLocal · timezone` validado contra IANA whitelist
- [x] `SLAPenalties` value object com invariantes financeiros enforced (`Money` fields)
  - Campos originais: `noShowPenaltyMultiplier · delayToleranceMinutes · delayPenaltyPerMinute · downgradePenaltyFlat`
  - **Expandido (Sprint 5.10 Fase 2):** `noShowThresholdMinutes (default 60) · earlyArrivalToleranceMinutes (default 5) · dwellTimeMinutes (default 3)`
  - Backward compat garantida via `fromJson()` com `?? default`. Sem migração SQL — campos vivem no JSONB.
  - Engine integration dos 3 novos campos: deferred para sprint posterior.
- [x] `PlanDeclaration` refatorado: aceita `List<ShiftPattern>` na criação
- [x] `ShiftProjectionService`: projeta SETs determinísticos; snapshots coordenadas da zona; `setId = SHA-256(planDeclarationId + shiftPatternIndex + operationalDate)`
- [x] `OperationalZoneRepository` interface (domínio puro)
- [x] **ADR registrado:** exceção ao invariante UTC para `ShiftPattern.arrivalTimeLocal` (ver Invariantes acima)

#### [x] 5.8 — Engine & Projection Upgrade
- [x] `ShiftProjectionService` acionado pelo `DeclareContractualPlanHandler` (projeta N=7 dias iniciais)
- [x] Gap detection: `ShiftProjectionService.detectAndAlertGaps()` — dias sem SETs em planos ativos geram `OperationalAlert` PROJECTION_GAP / CRITICAL
- [x] `InMemoryOperationalZoneRepository` + `PostgresOperationalZoneRepository`
- [x] `DeclareContractualPlanHandler` refatorado para aceitar `List<ShiftPattern>` no command

#### [x] 5.9 — UI Overhaul
- [x] Tela de gestão de `OperationalZone` (criar/listar — dentro do OCC Admin, pré-requisito para declaração de plano)
- [x] `DeclareContractPlanForm` refatorado como wizard de 4 etapas:
  1. Zonas de origem e destino (autocomplete de `OperationalZone` da org; inline "Criar primeira zona" se lista vazia)
  2. Padrão de turno: dias da semana (checkboxes), horário de chegada e partida (time picker — horário local exibido)
  3. SLA e penalidades: multiplicador de no-show, tolerância de atraso (min), valor por minuto (R$), downgrade (categoria + valor flat R$)
  4. Revisão e publicação: resumo com projeção de X viagens nos próximos 7 dias, aviso de imutabilidade do plano
- Rótulos pt-BR: `OperationalZone` → "Zona Operacional" · `ShiftPattern` → "Padrão de Turno" · SET → "Viagem Programada" (sem alteração)

#### [ ] 5.12 — Final Operational Validation
> **Renomeado de "5.10 Validation Consolidada" em 2026-03-12.** O fluxo de cadastro prévio de
> zonas foi considerado burocrático pelo PO e substituído pelo fluxo Just-in-Time (Sprint 5.12).
> A validação manual agora cobre o fluxo completo **com criação inline de zonas**.
>
> **⚠️ PRÉ-REQUISITO:** Sprint 5.12 (Fases B e C) **100% concluída** + `flutter test` verde +
> migrations `20260311000003` + `20260312000001/2/3` confirmadas no Supabase dev.
> A validação manual ocorre sobre a interface **final** — sem regressão pós-5.12.
>
> Cobre cenários originais da 5.4 (suspensa), todos os cenários B2B, e o novo fluxo JIT.
> **QA & SECURITY ENFORCEMENT:** Devido ao Ceticismo In-Memory, testes de idempotência e isolamento (multi-tenant) devem ser validados obrigatoriamente contra o banco de dados físico (Postgres), e a migration 5.6 deve ser confirmada.

**Cenários automatizados:**
- Cenário 5.1: Plano declarado com `ShiftPattern` gera ledger entry `PLAN_DECLARED` — mesmo comportamento da API
- Cenário 5.2: Plano publicado não pode ser editado — nova versão deve ser declarada
- Cenário 5.3: (**Postgres RLS**) Operador de Org A não vê contratos nem zonas de Org B nem via API
- Cenário 5.4: Contrato encerrado não aceita novos planos
- Cenário 5.5: `ShiftProjectionService` projeta mesmo SET para mesma data + mesmo ShiftPattern (determinismo)
- Cenário 5.6: (**Postgres Idempotency**) Projeção executada 2× gera 1 SET, não 2 (validação de unique constraint no banco físico)
- Cenário 5.7: Atualizar coordenadas de `OperationalZone` não altera SETs já projetados (snapshot enforced)
- Cenário 5.8: `ShiftPattern` com timezone inválida lança `DomainException` antes de qualquer persistência
- Cenário 5.9: Gap detection gera `OperationalAlert` CRITICAL quando dia esperado não tem SETs projetados

**⚠️ Testes Manuais Obrigatórios (Supabase dev ativo):**
- [ ] **Smoke test de UI existente (fases 3 e 4):** `InvestigationModal` e `ContractualAlertsPanel` renderizam sem erro com dados reais
- [ ] **Criar zona operacional inline** no Wizard Passo 1 (JIT) → confirmar que aparece na listagem de Zonas Operacionais com `organization_id` e `contractor_label` corretos no Supabase
- [ ] **Criar contrato + declarar plano** com ShiftPattern (incluindo zona criada inline) → confirmar que SETs projetados aparecem na aba Execuções com status `pending`
- [ ] **Determinismo de projeção:** declarar mesmo plano duas vezes → confirmar IDs de SETs idênticos, sem duplicatas no banco
- [ ] **Snapshot de zona:** alterar coordenadas de uma zona → confirmar que SETs anteriores mantêm coordenadas originais
- [ ] **Isolamento de tenant:** logar como Org A → confirmar que zonas e contratos de Org B não aparecem em nenhuma tela
- [ ] **Pipeline de avaliação:** SET projetado + telemetria simulada via Realtime → confirmar transição `pending → executed` sem refresh manual
- [ ] **Alert de gap:** forçar ausência de projeção para uma data → confirmar `OperationalAlert` PROJECTION_GAP aparece no painel

- [ ] **BLOCO 14 — Novos campos SLA:** Wizard Passo 3 exibe 3 grupos com 7 campos totais. Campos `noShowThresholdMinutes · earlyArrivalToleranceMinutes · dwellTimeMinutes` aparecem no JSONB do plano declarado (`SELECT shift_patterns_payload FROM plan_declarations WHERE ...`). Planos antigos (sem os 3 campos) ainda carregam sem erro.

- **Compliance Report:** `docs/governance/compliance/phase5_compliance_report.md`

---

### [~] Trilha B — UI/UX Standardization & Session Reliability
> **Por que agora:** Antecipado a pedido do Tech Lead. Para garantir que o Smoke Test manual seja executado sobre uma interface "Enterprise" sólida, com baixo estresse visual e navegação limpa.

#### [~] B1 — Padronização Visual (OCC)
> **Nota (2026-03-12):** O item "Alinhamento e Consistência" é parcialmente absorvido pela
> Sprint 5.11 (E1 `BusFlowSpacing` + E2 tipografia + E3 substituição de px raw nos formulários).
> Os 3 itens abaixo **NÃO** estão cobertos pela Sprint 5.11 e devem ser executados antes de
> emitir o Compliance Report da Phase 5.10 (qualquer inconsistência visual nos formulários
> enviesará o julgamento do smoke test manual).
- [x] **Alinhamento e Consistência:** Absorvido pela Sprint 5.11 (BusFlowSpacing, tipografia, grid 8px nos formulários de Zona e Contrato).
- [x] **Responsividade:** AppBar adapta título e FeedHealthBadge por breakpoint (≥600px); NavigationRail compacto (72px icon-only) substitui BottomNavBar em telas estreitas — elimina crash de 9 itens além do limite do Flutter.
- [x] **Stress Mode Toggle:** `_StressModeToggle` já presente na AppBar do `AdminLayout` desde Sprint 5.10. Confirmado como ítem estale.
- [x] **Localization (pt-BR):** `flutter_localizations` + delegates + `Locale('pt', 'BR')` já configurados em `main.dart`. Confirmado como ítem estale.

#### [x] B2 — Session Hook Reliability
- [x] **Fallback de Organização:** `organizationIdFetcherProvider` já implementado em `auth_providers.dart` — consulta `public.user_roles` quando `org_id` ausente no JWT. `currentOrganizationIdProvider` tenta JWT primeiro, cai no fallback assíncrono automaticamente.
- [x] **Validation Cleansing:** `addListener(_clearError)` adicionado em `_CreateZoneDialogState` e `_DeclareContractPlanFormState`. `create_contract_form.dart` já estava correto.

> **Nota de Conselho (2026-03-11):** Design Review realizado — fallback estava previamente implementado e correto. Validation Cleansing aplicado como hotfix nos 2 formulários pendentes.

#### [x] Sprint 5.10 Realignment — Ajustes de Domínio, Infra e UX
> **Origem:** Sessão do Conselho convocada em 2026-03-11 para revisar plano de ação técnico antes dos testes manuais (5.10).
> Itens aprovados e priorizados antes do smoke test para garantir que a interface e o domínio estejam "Enterprise-grade" antes da validação com dados reais.

**Todos os itens concluídos:**
- [x] `OperationalZone` — `GeofenceConfiguration?` VO (geofence opcional, nunca defaulta para 0.0/0.0)
- [x] `ZoneType` enum (`garagem · cliente · apoio`) e campo `address?` no aggregate
- [x] `ShiftProjectionService` — guarda invariante: lança `DomainException` se zona referenciada não tiver geofence
- [x] `PostgresOperationalZoneRepository` — lê/escreve nullable geo columns + `type` + `address`
- [x] UI (`OperationalZonesScreen`) — dropdown `ZoneType`, campo `address`, mapa em `ExpansionTile` (geofence opcional na criação)
- [x] Migration `20260311000002_operational_zone_business_fields.sql`
- [x] 13 testes atualizados para nova assinatura de `create`/`reconstitute` — 304 passing · 0 falhas
- [x] **TAREFA 1.2:** Null fallback `actorName ?? 'N/D'` em `operational_audit_screen.dart`
- [x] **TAREFA 3.1:** Tooltip financeiro no campo "Multiplicador No-Show" (`declare_contract_plan_form.dart`)
- [x] **TAREFA 3.2:** `'LINHA'` → `'ROTA'` no cabeçalho e painel de detalhe (`operational_audit_screen.dart`)
- [x] **TAREFA 3.3:** Filtro primário por `Contrato` na `BillingCycleReportsScreen` com aviso visual quando agregado

#### [x] Sprint 5.10 Fase 2 — Correções Críticas & Evolução SLAPenalties B2B
> **Origem:** Sessão do Conselho convocada em 2026-03-11. Testes manuais da Phase 5.10
> foram interrompidos por 6 bugs críticos. Paralelamente, o PO solicitou expansão do
> domínio SLA para refletir o mercado real de fretamento corporativo B2B.
> Aprovado pelo Conselho antes de retomar os testes manuais.
>
> **PRÉ-REQUISITO para retomar 5.10:** Esta sprint deve estar 100% concluída e migration
> `20260311000003` confirmada no Supabase dev antes de reiniciar o checklist de smoke test.

**BLOCO 1 — Correções Críticas (6 itens):**

| Item | Arquivo | Descrição |
|------|---------|-----------|
| **A1 [crash]** | `declare_contract_plan_form.dart:201` | `DayOfWeek.sort()` → `TypeError` ao publicar plano. Fix: `p.daysOfWeek.map((d) => d.value).toList()..sort()` |
| **A2 [SQL]** | `migrations/20260311000003_*.sql` | `column "created_at" does not exist` ao criar zona. Adicionar coluna idempotente. |
| **C1 [UX]** | `declare_contract_plan_form.dart` | Wizard Passo 1 usa `mockZones` hardcoded. Substituir por `ref.watch(operationalZonesProvider)` com AsyncValue exaustivo. |
| **C3 [a11y]** | `declare_contract_plan_form.dart` | Contraste ilegível no Passo 4 (`Colors.blue.shade50` + texto branco do tema dark). Fix: `BusFlowColors.info.withValues(alpha: 0.15)` + `BusFlowColors.textPrimary`. |
| **D1 [UX]** | `operational_zones_screen.dart` | `FlutterMap` sem geocoding gera falsa precisão. Remover mapa, substituir por 3 TextFields (lat/lng/radius) + aviso de obrigatoriedade + ícone `location_off` nas zonas sem geofence. |
| **E1 [nav]** | `create_contract_form.dart` + `contracts_screen.dart` | Após criar contrato, usuário retorna à lista sem direcionar. Pop com `contractId` + `ref.read(selectedContractIdProvider.notifier).state = contractId`. |

**BLOCO 2 — Evolução de Domínio (1 item, 3 novos campos):**

| Item | Arquivos | Descrição |
|------|---------|-----------|
| **B1 [domain]** | `sla_penalties.dart` | Adicionar `noShowThresholdMinutes (int, default 60)`, `earlyArrivalToleranceMinutes (int, default 5)`, `dwellTimeMinutes (int, default 3)`. Backward compat via `fromJson() ?? default`. Sem migração SQL — JSONB absorve. |
| **B2 [ui]** | `declare_contract_plan_form.dart` | Reorganizar Step 3 em 3 grupos: **Pontualidade e Janelas** · **Falhas Críticas** · **Qualidade da Frota**. 3 novos `TextEditingController`. `_submit()` lê e passa ao `SLAPenalties.create()`. |
| **B3 [tests]** | `shift_projection_service_test.dart` | Verificar 308 testes passando com defaults. Adicionar 1 teste (5.14) para os novos campos. |

**Status de execução:** ✅ CONCLUÍDA — 309 passing · 9 skipped · 0 falhas
- [x] A1 [crash] — DayOfWeek.sort() — fix 1 linha
- [x] A2 [SQL] — migration `20260311000003` criada e aplicada no Supabase dev ✅
- [x] B1 [domain] — SLAPenalties +3 campos com backward compat
- [x] B2 [ui] — Step 3 reorganizado em 3 grupos + 3 controllers + _submit() atualizado
- [x] B3 [tests] — 309 passing + teste 5.14
- [x] C1 [UX] — zonas reais via `operationalZonesProvider` + aviso de geofence ausente
- [x] C3 [a11y] — contraste Step 4 corrigido; todo o wizard migrado de `Colors.*` raw para `BusFlowColors.*` (black54 → textSecondary, grey.shade300 → border, red.shade50/200 → error.withValues, orange → warning)
- [x] D1 [UX] — FlutterMap removido; inputs manuais lat/lng/raio + `location_off` na listagem
- [x] E1 [nav] — `CreateContractForm.show()` retorna `String?` (contractId); `contracts_screen.dart` seta `selectedContractIdProvider`

**Arquivos modificados:**

| Arquivo | Tipo |
|---------|------|
| `lib/domain/sla_audit/sla_penalties.dart` | Domain — 3 novos campos |
| `lib/features/admin/presentation/screens/declare_contract_plan_form.dart` | UI — crash fix + zonas reais + Step 3 + contraste |
| `lib/features/admin/presentation/screens/operational_zones_screen.dart` | UI — remoção do mapa + inputs manuais |
| `lib/features/admin/presentation/screens/create_contract_form.dart` | Nav — retornar contractId |
| `lib/features/admin/presentation/screens/contracts_screen.dart` | Nav — set selectedContractIdProvider |
| `test/application/sla_audit/shift_projection_service_test.dart` | Testes — backward compat + teste 5.14 |
| `supabase/migrations/20260311000003_operational_zones_add_created_at.sql` | SQL — nova migration |
| `docs/testing/phase5_manual_test_log.csv` | Testes — BLOCO 14 para novos campos SLA |

---

#### [~] Sprint 5.11 — Anti-Fatigue & UX Excellence
> **Origem:** Redesenho Estratégico determinado pelo PO em 2026-03-12. Objetivo: erradicar a
> fadiga do operador nos fluxos de Cadastros (Zonas e Contratos). Conselho Completo convocado.
> Council Review concluído e plano aprovado. Fases A–E concluídas em 2026-03-12.

**Migrations aplicadas no Supabase dev (PO confirmou):**

| Migration | Arquivo | Status |
|-----------|---------|--------|
| `20260312000001` | `sla_templates.sql` | ✅ Aplicada |
| `20260312000002` | `contracts_clone_field.sql` | ✅ Aplicada |
| `20260312000003` | `operational_zones_contractor_label.sql` | ✅ Aplicada |

**FASE A — DB:** ✅ 3 migrations executadas e confirmadas pelo PO

**FASE B — Domain & Application:** ✅ CONCLUÍDA
- [x] **B1 [domain]** `SlaTemplate` entity + `SlaTemplateRepository` interface + `InMemorySlaTemplateRepository`
- [x] **B2 [command]** `CloneContractCommand` + `CloneContractHandler` — cria `draft`; `organization_id` do JWT; `cloned_from_contract_id` como campo de auditoria imutável
- [x] **B3 [domain]** `OperationalZone.create()` e `reconstitute()` aceitam `contractorLabel: String?`
- [x] **B4 [domain]** `Contract.createClone()` factory + `clonedFromContractId` field + `Contract.reconstitute()` atualizado

**FASE C — Infrastructure (Postgres):** ✅ CONCLUÍDA
- [x] **C1** `PostgresSlaTemplateRepository` — CRUD org-scoped
- [x] **C2** `PostgresContractRepository` — salva/lê `cloned_from_contract_id`
- [x] **C3** `PostgresOperationalZoneRepository` — salva/lê `contractor_label`

**FASE D — State (Riverpod):** ✅ CONCLUÍDA
- [x] **D1** `slaTemplatesProvider` (FutureProvider — lista org-scoped) em `sla_template_providers.dart`
- [x] **D2** `cloneContractHandlerProvider` (`Provider<CloneContractHandler>`) em `contract_providers.dart`

**FASE E — Design System:** ✅ CONCLUÍDA
- [x] **E1** `BusFlowSpacing` classe de constantes (base 8px: xs=4, sm=8, md=16, lg=24, xl=32, xxl=48) em `app_theme.dart`
- [x] **E2** `BusFlowTypography.dataValue` (15px w600 textPrimary) + `BusFlowTypography.fieldLabel` (11px w500 textSecondary) em `app_theme.dart`
- [x] **E3** Substituir valores px raw por `BusFlowSpacing.*` nos arquivos modificados nas fases F/G/H

**FASE F — UI — Wizard de Contrato (`declare_contract_plan_form.dart`):** ✅ CONCLUÍDA
- [x] **F1 [chips]** Step 2 — substituir `Checkbox` por `FilterChip` em `Wrap` para dias da semana (responde a `Space`)
- [x] **F2 [defaults]** Step 2 — `initState` pre-seleciona `America/Sao_Paulo` e `VehicleCategory.standard`
- [x] **F3 [funnel]** Step 1 — zonas agrupadas: "Cliente: X" (zonas com `contractor_label` == `contractorName` do contrato) acima de "Outras Zonas"
- [x] **F4 [template]** Step 3 — botão "Aplicar Template" no topo do step; abre bottom sheet com lista de `slaTemplatesProvider`; ao selecionar, preenche todos os controllers do Step 3
- [x] **F5 [disclosure]** Step 3 — `ExpansionTile("Opções Avançadas")` engloba `noShowThresholdMinutes`, `earlyArrivalToleranceMinutes`, `dwellTimeMinutes`
- [x] **F6 [keyboard]** `FocusNode` chain em todos os `TextFormField`; `onFieldSubmitted` avança ao próximo campo ou step; `Enter` no Step 4 aciona `_submit()`; `Escape` com confirmação

**FASE G — UI — Formulário de Zona (`operational_zones_screen.dart`):** ✅ CONCLUÍDA
- [x] **G1 [label]** Campo `contractor_label` (opcional) no formulário de criação/edição de zona
- [x] **G2 [disclosure]** Geofence (lat/lng/radius) em `ExpansionTile("Configuração de Geofence")` — opcional na criação
- [x] **G3 [keyboard]** FocusNode chain + Enter no último campo submete o formulário

**FASE H — UI — Tela de Contratos (`contracts_screen.dart`):** ✅ CONCLUÍDA
- [x] **H1** Botão "Clonar" no menu de ações de cada contrato (ícone `content_copy_rounded`)
- [x] **H2** Ao clonar, abrir `CreateContractForm` pré-preenchido + navegar para o rascunho criado

**FASE I — Testes automatizados:** ✅ CONCLUÍDA
- [x] `CloneContractHandler` — 9 testes (happy path · tenant isolation · invariantes de domínio) — 323 passing
- [x] Unit tests: `SlaTemplate.create()` (name validation, org isolation)
- [x] Unit tests: `OperationalZone.create()` com `contractorLabel` (trim, null quando vazio)
- [x] `flutter test` — 340 passing ✅
- [x] Novos arquivos: `sla_template_test.dart` (6 casos) e `operational_zone_test.dart` (10 casos)

**Critérios de Done:**
- [x] 3 migrations executadas e confirmadas pelo PO no Supabase dev
- [x] `flutter test` — 340 passing · 0 falhas ✅
- [x] Wizard navegável completamente via `Tab`/`Enter` sem mouse
- [x] Caminho feliz do Wizard: máx 4 campos visíveis por step (Opções Avançadas fechadas por padrão)
- [x] Template SLA preenche Step 3 em 1 clique
- [x] Clone de contrato persiste `cloned_from_contract_id` (validado por testes de domínio)
- [x] `BusFlowSpacing` usado em todos os arquivos F/G/H; 0 `Colors.*` raw em código novo
- [x] `dataValue` e `fieldLabel` aplicados nos formulários refatorados
- [x] 2 novos arquivos de teste: `sla_template_test.dart` e `operational_zone_test.dart`

**Compliance Report:** `docs/governance/compliance/phase5_11_compliance_report.md`

---

#### [ ] Sprint 5.12 — Just-in-Time Operational Awareness
> **Origem:** PO determinou em 2026-03-12 que o fluxo de cadastro prévio de zonas é burocrático.
> Substituído por cadastro inline no Wizard de Contrato sem sair do contexto.
> Design Spec e Council Review concluídos em 2026-03-12 antes do início da implementação.

**Objetivo:** Operador cadastra `OperationalZone` inline no Passo 1 do Wizard de Contrato.
`contractorLabel` herdado automaticamente de `contract.contractorName`. Sem nova migration SQL —
`contractor_label` já existe (`20260312000003`). Sem `CompositeCommand` — zonas são recursos
organizacionais independentes; criação eager via `saveZone()` existente é suficiente.

**FASE A — Design Spec & Council Review:** ✅ CONCLUÍDA (2026-03-12)

**FASE B — UI:** [ ] Em andamento
- [x] `operational_zones_screen.dart` — extensão `ZoneTypeUi` tornada pública/nomeada
- [x] `zone_type_ahead_field.dart` — widget `ZoneTypeAheadField` criado (autocomplete + mini-form inline + geofence warning)
- [x] `declare_contract_plan_form.dart` — `_buildStep1()` substituído; `_selectedOriginZone`/`_selectedDestinationZone` adicionados; `_resetForReturnShift()` atualizado
- [ ] Revisão visual no browser (smoke rápido)

**FASE C — Testes automatizados:** [ ] Pendente
- [ ] `test/features/admin/presentation/widgets/zone_type_ahead_field_test.dart` — filtro unitário + widget tests

**FASE D — 5.12 Final Operational Validation:** [ ] Bloqueada até Fases B e C concluídas
> Ver seção "5.12 Final Operational Validation" abaixo.

**Critérios de Done:**
- [ ] `flutter test` — ≥ 340 passing · 0 falhas
- [ ] Digitar nome inexistente no campo de zona → `'+ Criar zona "X"'` visível no overlay
- [ ] Zona criada inline aparece na aba Zonas Operacionais com `contractorLabel` correto
- [ ] Swap origem↔destino (return shift): texto nos dois campos trocado corretamente
- [ ] Geofence hard block inalterado: zona sem geofence bloqueia avanço ao Passo 2
- [ ] Zona existente selecionável normalmente (sem regressão)

---

#### [x] B3 — Contractual Risk Radar (Dashboard Pivot)
> **Definido via Reunião do Conselho (10/Mar):** Pivotar a tela inicial para focar em métricas financeiras e obrigações, eliminando o mapa como componente central diário.

- [x] **Arquitetura (CQRS):** Criar `dashboardRiskFeedProvider` consumindo estritamente as *Projections* de leitura (`timelineProjection`) sem ferir limites do domínio.
- [x] **Segurança (RLS):** Garantir Tenant Isolation na agregação de turnos e alertas do feed principal.
- [x] **Apresentação (UI/UX):** Remover `HeatmapSection`. Injetar `ContractualRiskRadar` com KPIs CFO-Friendly (Receita em Risco/SLA Violado).
- [x] **Timeline Feed:** Listar as *Viagens Programadas* do dia atual, ordenando por severidade (CRITICAL > WARNING > ON_TIME).
- [x] **Mapa Analítico:** Restringir o FlutterMap ao `InvestigationModal` (sob demanda).

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
[~] Phase 5  Contract & Plan Lifecycle Management (B2B Refactoring)  ← em andamento
     ✅ 5.1 Design Spec (baseline)
     ✅ 5.2 Council Review (baseline)
     ✅ 5.3 Implementation (baseline — supersedida)
     ✅ 5.4 Validation (suspensa → incorporada em 5.10)
     ─ ─ ─  B2B Refactoring  ─ ─ ─
     ✅ Design Spec B2B (OperationalZone · ShiftPattern · SLAPenalties)
     ✅ Council Review B2B (4 BLOCKERs · Opção A selecionada)
     ✅ 5.5 Blocker Resolution
     ✅ 5.6 Database Foundation (migrations 000000 · 000002 · 000003)
     ✅ 5.7 Domain Refactoring
     ✅ 5.8 Engine & Projection Upgrade
     ✅ 5.9 UI Overhaul
✅ Trilha B UI/UX Standardization & Session Reliability
     ✅ B1 Padronização Visual (OCC)
           ✅ Alinhamento e Consistência → absorvido por Sprint 5.11
           ✅ Responsividade (AppBar · Sidebar · NavigationRail compacto)
           ✅ Stress Mode Toggle (já na AppBar — ítem estale confirmado)
           ✅ Localization pt-BR (já configurado em main.dart — ítem estale confirmado)
     ✅ B2 Session Hook Reliability
     ✅ B3 Contractual Risk Radar (Pivot)
     ✅ Sprint 5.10 Realignment (domínio · infra · UX)
     ✅ Sprint 5.10 Fase 2 — Bug Fixes & SLAPenalties B2B
[x] Sprint 5.11 Anti-Fatigue & UX Excellence           ← CONCLUÍDA
     ✅ Fase A — DB (3 migrations)
     ✅ Fase B — Domain (SlaTemplate · CloneContract · OperationalZone.contractorLabel)
     ✅ Fase C — Infra Postgres
     ✅ Fase D — Riverpod Providers
     ✅ Fase E1/E2 — Design System (BusFlowSpacing · dataValue · fieldLabel)
     ✅ Fase E3 — BusFlowSpacing nos arquivos de UI
     ✅ Fase F — Wizard UI (chips · defaults · funil · template · disclosure · teclado)
     ✅ Fase G — Zona UI (contractor_label · geofence disclosure · teclado)
     ✅ Fase H — Contratos UI (botão Clonar)
     ✅ Fase I — Testes (340 passing)
─ ─ ─  antes de 5.10 Validation  ─ ─ ─
     ✅ B1 remanescente: Responsividade · Stress Mode Toggle · Localization pt-BR
─────────────────────────────────────────────────────
[ ] 5.10 Validation Consolidada (testes manuais)
     PRÉ-REQ: Sprint 5.11 concluída + B1 remanescente + migrations 000000–000003 + 20260312000001–3 ✅
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

**Sprint 5.11 concluída. Próxima ação: 5.10 Validation (Testes Manuais de Fumaça).**

### Sequência imediata

```
1. [ ] 5.10 Validation     — Testes manuais (smoke test completo com Supabase dev ativo)
2. [ ] Phase 6             — Administration & Tenant Self-Service
3. [ ] Phase 7             — Evidence & Audit Exports
```

### Atenção: itens que PODEM afetar trabalho já concluído

| Risco | Fase futura | Mitigação já documentada |
|-------|-------------|--------------------------|
| `Contractor` aggregate (Phase 6) pode exigir migrar `contractor_label TEXT` → FK | Phase 6.3 | Documentado como migração planejada; `contractor_label` é tag temporária por design |
| B1 Localization pt-BR altera widgets de calendário usados no Wizard | ~~B1 remanescente~~ | ✅ Resolvido — localization já configurada, smoke test pode prosseguir |
| `PostgresSlaTemplateRepository` usava `dynamic` | ~~Phase 8.4~~ | ✅ Corrigido em Sprint 5.11 — `List<Map<String,dynamic>>` strict |
| `supabase_smoke_test.dart:2.2` falha por falta de inicialização de timezone em teste puro | ~~Débito técnico~~ | ✅ Corrigido em Sprint 5.11 — `setUpAll` incondicional chama `BrazilTime.ensureInitialized()` |
