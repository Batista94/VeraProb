# PactaFlow — Roadmap Estratégico

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---------|--------|
| Testes | 568 passing · 0 falhas ✅ |
| Análise estática | 0 erros · 75 infos |
| Precisão financeira | `Money` (centavos BIGINT) — Enforced ✅ |
| Sprint 5.11 - 5.12 | **CONCLUÍDAS** — JIT Master Data, RLS, UTC. |
| Sprint 5.13 | **CONCLUÍDA** — Teto Financeiro, Carência (Grace Period) e Risk KPIs. ✅ |
| Phase 6 | **CONCLUÍDA** — Administration, RBAC, Invitations e Approval Workflow. ✅ |
| Bloco 8 | **CONCLUÍDO** — Asset Manager, `organization_id` isolation, tabbed CRUD. ✅ |
| Phase 6.5 | **CONCLUÍDA** — Anti-Corruption Edge, Chaos Tolerance, Asset State Machine, Kinematic Filter. ✅ |
| Banco de dev | Todas as migrations aplicadas — `20260325...` |

## Fases Pendentes (Próximas Etapas)

### [x] Phase 6.5 — Operational Resilience & Ingestion Architecture 🌊 ✅
**Objetivo:** Preparar a plataforma para o caos do mundo real (atrasos de telemetria, ruído de hardware e integração com terceiros).

#### [x] 6.5.1 — Anti-Corruption Edge (Adapters) ✅
- **Design:** Adapters via Supabase Edge Functions (Sascar/Omnitracs). INV-16 + INV-17 propostos e implementados.
- **Review:** `provider_api_keys` isolam `organization_id` do payload. Raw blobs selados com SHA-256.
- **Implementation:** `ingest-sascar` + `ingest-omnitracs` Edge Functions. `CanonicalFact` domain entity. `IngestionIntegrityFlag` enum. Tabelas: `provider_api_keys`, `raw_telemetry_payloads` (com `payload_hash`), `canonical_facts`. Idempotência via hash garantida.
- **Validation:** 28 testes domain + Smoke test OK (accepted + LATE_ARRIVAL). 481 testes no total. ✅

#### [x] 6.5.2 — Chronological Chaos Tolerance ✅
- **Design:** `TelemetryIngestionPipeline` — ordena por `gps_timestamp ASC`. Separação `received_at_utc` de `gps_timestamp` (INV-16).
- **Review:** `lateArrival` facts são processados; retroactive invalidation delegado a Phase 7.5.1. Filtro `NULL_ISLAND` integrado.
- **Implementation:** `TelemetryIngestionPipeline` + `CanonicalFactRepository` + in-memory impl.
- **Validation:** 5 testes de chaos (ordering, late arrival, futureTimestamp, nullIsland, totals). ✅

#### [x] 6.5.3 — Asset State Machine ✅
- **Design:** `AssetStatus` enum (active/maintenance/offDuty) + `AssetStatusEvent` (event-sourced).
- **Review:** `MAINTENANCE` e `OFF_DUTY` suprimem avaliação no pipeline — zero falsos positivos (INV-13).
- **Implementation:** `AssetStatusRepository` + `InMemoryAssetStatusRepository` + migration `asset_status_events` + `get_current_asset_status()` function.
- **Validation:** 6 testes (maintenance suppression, off-duty, default active, replay, UTC invariant).

#### [x] 6.5.4 — Kinematic Noise Filter ✅
- **Design:** Filtro Haversine sequencial em `TelemetryIngestionPipeline` (stateful, in-memory por run). Edge Functions fazem checks single-point; pipeline faz checks sequenciais.
- **Review:** Devices isolados — state de Device A não contamina Device B.
- **Implementation:** `_haversineMeters` check em `TelemetryIngestionPipeline.process()`. Max 200 km/h implícito.
- **Validation:** 4 testes (200m jitter, same-timestamp glitch, valid 80km/h movement, device isolation).

---

### [x] Phase 7 — Evidence & Audit Exports ✅


**Por que depois de Phase 6:** Exportações são o produto que o cliente entrega ao seu próprio cliente
(empresa de transporte entregando relatório de SLA ao contratante). Só faz sentido gerar esse produto
quando a plataforma tem clientes reais com dados reais fluindo.

**Nota:** Fundação parcialmente implementada — `BillingCycleReport` domain entity completo com
agregação determinística e ID canônico. `BillingCycleReportsScreen` existe com estrutura UI.
Phase 7 completa e formaliza essa fundação.

**Objetivo:** Transformar os snapshots financeiros imutáveis em evidências acionáveis —
relatórios de conformidade, exports para controladoria e auditoria, dashboard executivo.

#### [x] 7.1 — Design Specification ✅

**Artefato:** `docs/architecture/11_evidence_audit_exports_design.md`

Cobrir obrigatoriamente:
- **Billing Cycle Report:** completar implementação da `BillingCycleReportsScreen` (CSV export, período customizável, filtro por contrato)
- **Monthly Compliance Report:** aggregation pipeline usando `pg_cron` (job mensal por org/contrato)
- **PDF export:** layout de relatório para auditoria (cabeçalho, sumário executivo, detalhamento por SET)
- **Executive Dashboard:** KPIs agregados — taxa de compliance, receita protegida/em risco/perdida por período
- **Provenance chain:** relatório exportado referencia `snapshotIds` e `ledgerEntryIds` — rastreável ao evento original
- **Imutabilidade:** relatórios gerados são read-only — qualquer regeneração cria nova versão, nunca sobrescreve
- **Tenant scoping:** jobs `pg_cron` processam 1 `organization_id` por vez — sem cross-tenant analytics
- **Portal de Transparência do Contratante:** Dashboard executivo de acesso restrito ao contratante. KPIs: `Receita Protegida` vs `Multas Recuperadas`. Download autônomo de relatórios de conformidade e evidências sem intervenção do operador.
  - **Design:** Wireframe do dashboard externo e tokens de acesso por contratante.
  - **Review:** Garantir que contratante acesse apenas seus próprios contratos (Zero Trust).
  - **Implementation:** Criar rotas de apresentação e aggregators financeiros específicos.
  - **Validation:** Smoke test de login de contratante e exportação autônoma de CSV.

#### [x] 7.2 — Council Review ✅

Validar antes de implementar:
- Jobs de aggregation operam sobre snapshots imutáveis, não sobre o ledger bruto
- Export CSV/PDF derivado dos snapshots do período — replay produz o mesmo arquivo
- `pg_cron` jobs include `organization_id` explícito — sem scans globais
- Relatório exportado não pode ser alterado após gerado

#### [x] 7.3 — Implementation ✅

- **SQL:** `monthly_compliance_reports` table, `pg_cron` jobs de fechamento mensal, indexes
- **Domain:** `ComplianceReport` entity (se necessário além de `BillingCycleReport`)
- **Application:** `ReportGenerationService`, `CsvExportService`, `PdfExportService`
- **Infrastructure:** Repositórios para reports, integração `pg_cron`
- **Presentation:**
  - Completar `BillingCycleReportsScreen` (export CSV funcional, seleção de período)
  - Tela de relatórios mensais de compliance
  - Export PDF para auditoria
  - Executive Dashboard com KPIs por período
  - Portal de Transparência (Dashboard executivo + export autônomo)
    - **Design:** (Conforme especificado em 7.1)
    - **Review:** Validar consistência dos KPIs financeiros entre portal e admin.
    - **Implementation:** Implementar UI do dashboard de transparência.
    - **Validation:** Confirmar que download de evidências funciona via link direto do portal.

#### [x] 7.4 — Validation ✅


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

### [x] Phase 7.5 — Financial Defense & Shadow Mode 🛡️ ✅

**Objetivo:** Criar mecanismos indestrutíveis de prova judicial (Apelo) e simulação de ROI acelerada (Shadow Mode).

#### [x] 7.5.1 — Tribunal de Apelações (Compensating Transactions) ✅

- **Design:** Registro contábil de estorno/crédito vinculado a débito existente.
- **Review (@qa_security):** Proibir modificação do passado; exigir trilha de evidência (`evidence_locker_id`).
- **Implementation:** UI de estorno de multa e lógica de neutralização no Ledger.
- **Validation:** Auditoria: Verificar se o registro original permanece intacto após o perdão.

#### [x] 7.5.2 — Shadow Mode (Batch Import Engine) ✅

- **Design:** Bulk Ingestion de dados históricos para simulação de contratos.
- **Review:** Garantir isolamento total do ambiente de produção (`shadow_tenant`).
- **Implementation:** Worker de importação CSV e pipeline RuleEngine para dados retroativos.
- **Validation:** Provar ROI para CFO em menos de 10 segundos com relatório comparativo.

#### [x] 7.5.3 — Forensic Hardening ✅

- **Design:** Habilitar `pgaudit` e triggers de rejeição de DELETE para superuser.
- **Review:** Blindagem contra "The Superuser Loophole".
- **Implementation:** Configuração de integridade a nível PostgreSQL.
- **Validation:** Tentar deletar uma linha do Ledger como admin e receber erro 403 DB level.

### [ ] Phase 8 — Operational Hardening

**Por que depois de Phase 7:** O hardening operacional prepara o produto para receber tráfego real.
Executá-lo antes de ter todas as features seriam contraproducente.

#### [x] 8.1 — Systemic UX, Hard Gates & Dual-Key RLS ✅


**Fonte da Verdade:** [`docs/architecture/12_systemic_user_journeys.md`](../architecture/12_systemic_user_journeys.md)

**Objetivo:** Enforcar o fluxo sistêmico do PactaFlow na camada de domínio e infraestrutura. Não se trata apenas de UX — é a garantia de que o engine nunca acorda sem contexto e que um contractor nunca acessa dados de outro.

**Invariantes ratificadas:** INV-18 · INV-19 · INV-20

##### [x] 8.1.1 — Hard Gate: Engine Activation (INV-18) ✅
- **Domain/Application:** Adicionar guard em `DeclareContractualPlanHandler` (`lib/application/sla_audit/declare_contractual_plan_handler.dart`)
  - `operationalZoneRepository.countByOrg(organizationId) > 0` → throw `DomainException('No operational zones configured for this organization')`
  - Se shift-based: `vehicleRepository.countActive(organizationId) > 0` → throw `DomainException('No active vehicles found for this organization')`
- **Testes:** 2 novos testes unitários no handler (zona ausente → exception, veículo ausente em shift-based → exception)

##### [x] 8.1.2 — Hard Gate: On-The-Fly Contractor Creation (INV-19) ✅
- **Flutter:** Adicionar `ContractorSelectorField` (typeahead) em `CreateContractForm` (`lib/features/admin/presentation/screens/create_contract_form.dart`)
  - Se lista vazia ou nome não encontrado → exibir "+ Criar '[nome]' como Contractor"
  - Abre `SaveContractorModal` como `showDialog()` overlay — NÃO navega
  - Após salvar, injeta o novo contractor no campo sem fechar o formulário pai
- **Invariante:** O formulário pai nunca perde estado durante a criação de dependência

##### [x] 8.1.3 — Dual-Key RLS para CONTRACTOR_VIEWER (INV-20) ✅
- **SQL — Migration:** `[timestamp]_contractor_viewer_role.sql`
  - Adicionar coluna `contractor_id UUID REFERENCES contractors(id)` em `user_roles`
  - Atualizar `custom_access_token_hook` para injetar `app_metadata.contractor_id` quando `role = 'CONTRACTOR_VIEWER'`
  - Injetar `contractor_id = NULL` explicitamente para roles internas (admin, operator, auditor)
- **SQL — RLS:** Adicionar política dual-keyed em `audit_packages` e demais tabelas do portal do contractor:
  ```sql
  USING (
    organization_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
    AND contractor_id = (auth.jwt() -> 'app_metadata' ->> 'contractor_id')::uuid
  )
  ```
- **BLOCKER:** PO deve confirmar *"SQL executado no SQL Editor do Supabase"* antes da implementação Flutter

##### [x] 8.1.4 — Correção de JWT Path em audit_packages (Technical Debt) ✅
- **SQL:** Corrigir RLS de `audit_packages` de `(auth.jwt() ->> 'organization_id')::uuid` para `(auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid` (alinhar com INV-10)
- **Arquivo:** `supabase/migrations/20260401000001_audit_packages.sql` (linha 108-115)
- **Nota:** Executar ANTES de 8.1.3 para evitar conflito de políticas

##### [x] 8.1.5 — OnboardingProgressBanner (UX) ✅
- **Flutter:** Novo widget `OnboardingProgressBanner` em `lib/presentation/shell/admin_shell.dart`
  - Exibe: Zonas ✓/✗ · Contractors ✓/✗ · Veículos ✓/✗ · SLA Template ✓/✗
  - Itens clicáveis → navegam para tela correspondente
  - Desaparece automaticamente quando todos os 4 pré-requisitos satisfeitos
  - Providers: `operationalZonesProvider`, `contractorListProvider`, `vehicleListProvider`, `activeRulesProvider`

##### [x] 8.1.6 — UX Refactoring & Visual Enterprise Standard ✅
**Auditoria visual Phase 8.1 — resultado: UI aparenta protótipo, não SaaS B2B Enterprise.**

###### Cluster 1 — Onboarding Banner (8.1.5 Refinement)
- Itens com ✓ não devem ser clicáveis nem ter hover state → desabilitar `onTap` quando `isFulfilled`
- Substituir card intrusivo por top bar slim (strip de ~48px) que não desloca layout
- Auto-hide ao cumprir os 4 requisitos: já implementado via `SizedBox.shrink()` ✅

###### Cluster 2 — Hierarquia Visual / Acessibilidade WCAG
- Auditar contraste de `textSecondary` sobre `background` (target: WCAG AA ≥ 4.5:1)
- Inputs "boxy": adicionar whitespace interno e border-radius suave no `InputDecorationTheme` (`app_theme.dart`)
- **Bug 2.2:** `_DatePickerField` e todos os campos de data devem ter `floatingLabelBehavior: FloatingLabelBehavior.always` — evitar sobreposição hint/label (`create_contract_form.dart`)

###### Cluster 3 — Sidebar / Navegação / Resiliência (AdminLayout)
- **Bug VETADO:** clicar na mesma rota atual redireciona para Dashboard (index 0) — comportamento inaceitável
  → Fix: `if (index == selectedIndex) return;` (no-op) em `onDestinationSelected` (`admin_layout.dart:119`)
- **Bug 1.2:** overflow em telas menores → `SingleChildScrollView` já envolve o `NavigationRail` ✅
- **Bug 1.3:** `_InternalBackButton` já existe para contratos ✅ · auditar drawers de detalhe restantes

###### Cluster 4 — Formulários e Modais
- **Bug 2.1:** formatação BRL inconsistente → unificar em `NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ')` — eliminar `_formatCents()` manual em `declare_contract_plan_form.dart`
- **Bug 2.3:** modais quebram em altura baixa → `SingleChildScrollView` em `occurrence_modal.dart` · `maxHeight` responsivo em `declare_contract_plan_form.dart`

**Personas:** `senior_engineer` (8.1.1, 8.1.2, 8.1.5, 8.1.6) · `qa_security` (8.1.3, 8.1.4) · `ux_operations` (8.1.6)

#### [ ] 8.2 — CI/CD Pipeline
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

#### [x] 8.3 — Separação de Ambientes (Technical Debt) ✅
- [x] **Environments Configuration**: `lib/core/config/environment.dart` — `AppEnvironment` enum + `EnvironmentConfig`. `supabase_client.dart` atualizado. ✅
- [x] **`--dart-define` por ambiente**: `run_dev.ps1` · `run_staging.ps1` · `.env.example` ampliado · `docs/operations/environments.md` ✅
- [x] **3 projetos Supabase**: PO deve criar `PactaFlow-dev` · `PactaFlow-staging` · `PactaFlow-prod` no Supabase Dashboard (Documentado em `docs/operations/environments.md`) ✅
- [ ] **Migrations Pipeline**: Migrar de "Copy-Paste no SQL Editor" para `supabase db push` via CLI (pré-requisito: 8.2 CI/CD)
- [ ] **Edge Functions CI**: Automação de deploy para triggers e hooks (pré-requisito: 8.2 CI/CD)
- [ ] **Monitoramento**: Integração Sentry/PostHog — coberto em 8.4 Observabilidade
- [x] **Processo de promoção**: dev → staging → prod documentado em `docs/operations/environments.md` ✅ · Automação via CI/CD (8.2)
- [x] Dados de teste **nunca** chegam em prod — documentado como regra em `docs/operations/environments.md` ✅

#### [ ] 8.4 — Observabilidade
- Error tracking: Sentry (Flutter SDK + Supabase Edge Functions)
- Logging estruturado: JSON com `organization_id`, `user_id`, `correlation_id` em cada entrada
- Substituir todos os `print()` por logger estruturado (detectáveis via `avoid_print` já ativo)
- Alertas: notificação se ledger write > 2s ou taxa de erro > 1%

#### [ ] 8.5 — Segurança (Hardening Final)
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

#### [ ] 8.6 — Performance & Escala
- Load test: 1.000 veículos simultâneos com telemetria contínua
- Benchmark `ContractualEvaluationEngine` (meta: < 100ms por vehicle state)
- Revisão de índices com base nas queries reais de staging
- Avaliar read replicas para queries de relatório (não competir com writes do ledger)

#### [ ] 8.7 — Disaster Recovery
- Documentar estratégia de backup (Supabase PITR — Point-in-Time Recovery)
- Runbook de restore com tempo estimado e responsável pela autorização
- Definir RPO/RTO para dados financeiros (meta: RPO ≤ 1h · RTO ≤ 4h)
- Testar restore em ambiente isolado ao menos 1× antes do lançamento

#### [ ] 8.8 — Auditoria de Integridade de Telemetria (Anti-Spoofing)
- **Detectar Fake GPS:** saltos lógicos de posição (velocidade física impossível entre dois pontos)
- **Detectar sinal manipulado:** baixo número de satélites + coordenadas fixas por longo período
- **Engine invalida evidências suspeitas com flag `TELEMETRY_INTEGRITY_VIOLATION` antes de emitir veredito**
  - **Design:** Algoritmo de detecção de anomalias cinemáticas e limite de satélites.
  - **Review:** Validar impacto de falso-positivos em áreas de sombra de GPS.
  - **Implementation:** Integrar engine de anti-spoofing no pipeline de avaliação.
  - **Validation:** Testar com datasets de spoofing conhecido e verificar flags no vederito.
- **Personas:** `qa_security`, `architect`

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
> **Este é o maior teste manual do produto** — realizado por usuários reais, not pelo desenvolvedor.

- Selecionar 2–3 clientes reais com contratos de transporte ativos
- Monitoramento intensivo durante o piloto (Sentry + contato direto)
- Coleta estruturada de feedback a cada 2 semanas
- **Critério de saída do beta:** zero incidentes críticos em 30 dias corridos
- Ajustes de produto incorporados antes do lançamento

---

## Fases Concluídas (Histórico)

### [x] Phase 7 — Evidence & Audit Exports ✅
*Relatórios de conformidade, CSV/PDF com digital sealing (INV-16/17), Prova de Execução, Executive Dashboard e Portal de Transparência do Contratante.*

### [x] Phase 7.5 — Financial Defense & Shadow Mode 🛡️ ✅
*Shadow Mode (Batch Import ROI), Tribunal de Apelações (Compensating Transactions) e Blindagem Forense PostgreSQL. 568 testes operando.*

### [x] Phase 6.5 — Operational Resilience & Ingestion Architecture ✅

### [x] Phase 6 — Administration & Tenant Self-Service ✅
*RBAC, Gestão de Organização, Convites, Workflow de Aprovação de Contratos e Wizard de Onboarding.*

### [x] Phase 5 — B2B Refactoring & Foundation ✅
*Implementação de JIT Master Data, RLS Tenant Isolation, Teto Financeiro e Evidence Locker.*

---

## Visão Geral de Execução

─────────────────────────────────────────────────────
[x] Phase 5 — B2B Refactoring (Sprints 5.11, 5.12, 5.13) ✅
─────────────────────────────────────────────────────
[x] Phase 6 — Administration & Tenant Self-Service ✅
─────────────────────────────────────────────────────
[x] Phase 6.5 — Operational Resilience 🌊 ✅
─────────────────────────────────────────────────────
[x] Phase 7 — Evidence & Audit Exports ✅
─────────────────────────────────────────────────────
[x] Phase 7.5 — Financial Defense & Shadow Mode 🛡️ ✅
─────────────────────────────────────────────────────
[x] Phase 8 — Operational Hardening (Sprint 8.1 COMPLETE) ✅
─────────────────────────────────────────────────────

### Próximo passo: Phase 8 — Operational Hardening
Preparar o fluxo sistêmico e a infraestrutura para produção real.
1. [x] 8.1 Systemic UX, Hard Gates & Dual-Key RLS ✅
2. [ ] 8.2 CI/CD Pipeline
3. [x] 8.3 Separação de Ambientes ✅
4. [ ] 8.4 Observabilidade (Sentry/PostHog)
5. [ ] 8.5 Segurança (Strict-casts & RLS audit)
