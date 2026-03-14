# PactaFlow — Roadmap Estratégico

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

## Fases Pendentes

> Ordem de execução é obrigatória — fases não podem ser puladas (`.cursorrules`).

---

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

#### [ ] Sprint 5.12 Phase D — Refinement & Security Hotfixes
> **Origem:** Auditoria interna e feedback técnico (2026-03-13). 
> Aborda débitos técnicos de precisão financeira, sincronização UTC e segurança RLS.

- [ ] **Step 1 (UI Fix):** `ZoneTypeAheadField` — Corrigir rebuild síncrono e listener duplicado em `fieldViewBuilder` usando `initialValue` no Autocomplete.
- [ ] **Step 2 (UTC):** Garantir `.toUtc()` no `InMemoryPolicyEvaluator` e `VehiclePosition.isStale()`.
- [ ] **Step 3 (Doc):** Atualizar `sql/schema_sla_audit.sql` para refletir `contractual_value_cents BIGINT` (stale ref fix).
- [ ] **Step 4 (SQL - BLOCKING):** Migration `20260313000001` (CSE Tenant Isolation). **Aguardando PO executar no SQL Editor.**
- [ ] **Step 5 (Infra):** Incluir `organization_id` nos inserts de `contractual_service_executions` em `PostgresPlanDeclarationRepository`.

#### [ ] 5.12 Final Operational Validation

**Critérios de Done:**
- [ ] `flutter test` — ≥ 340 passing · 0 falhas
- [ ] Digitar nome inexistente no campo de zona → `'+ Criar zona "X"'` visível no overlay
- [ ] Zona criada inline aparece na aba Zonas Operacionais com `contractorLabel` correto
- [ ] Swap origem↔destino (return shift): texto nos dois campos trocado corretamente
- [ ] Geofence hard block inalterado: zona sem geofence bloqueia avanço ao Passo 2
- [ ] Zona existente selecionável normalmente (sem regressão)
- [ ] Zona criada via modal é auto-selecionada no campo (sem redigitar)
- [ ] Autocomplete de Contratante em Zonas Operacionais sugere nomes de contratos existentes

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
─────────────────────────────────────────────────────
─────────────────────────────────────────────────────
[ ] Sprint 5.12 Phase D — Refinement & Security Hotfixes (INV-2 · INV-3 · INV-6)
     [ ] Step 1 UI Rebuild Fix
     [ ] Step 2 UTC Standardization
     [ ] Step 3 Stale Schema Doc
     [ ] Step 4 SQL Migration (Tenant Isolation)
     [ ] Step 5 Infra Org Isolation
─────────────────────────────────────────────────────
[ ] 5.12 Final Operational Validation (testes manuais)
     PRÉ-REQ: Sprint 5.11 concluída + B1 remanescente + Sprint 5.12 Phase D concluída + migrations ✅
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
1. [ ] 5.12 Phase D Refinement — Hotfixes críticos (INV-2, INV-3, INV-6)
2. [ ] 5.12 Final Validation   — Testes manuais (smoke test completo)
3. [ ] Phase 6                — Administration & Tenant Self-Service
```

### Atenção: itens que PODEM afetar trabalho já concluído

| Risco | Fase futura | Mitigação já documentada |
|-------|-------------|--------------------------|
| `Contractor` aggregate (Phase 6) pode exigir migrar `contractor_label TEXT` → FK | Phase 6.3 | Documentado como migração planejada; `contractor_label` é tag temporária por design |
| B1 Localization pt-BR altera widgets de calendário usados no Wizard | ~~B1 remanescente~~ | ✅ Resolvido — localization já configurada, smoke test pode prosseguir |
| `PostgresSlaTemplateRepository` usava `dynamic` | ~~Phase 8.4~~ | ✅ Corrigido em Sprint 5.11 — `List<Map<String,dynamic>>` strict |
| `supabase_smoke_test.dart:2.2` falha por falta de inicialização de timezone em teste puro | ~~Débito técnico~~ | ✅ Corrigido em Sprint 5.11 — `setUpAll` incondicional chama `BrazilTime.ensureInitialized()` |
