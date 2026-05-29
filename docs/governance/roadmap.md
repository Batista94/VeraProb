# VeraProb — Active Strategic Roadmap

**Revision:** 2026-04-01
**Current Status:** Phase 10.4.B — First Tenant Activation Gate · [NEXT: 10.5 - First Pilot]
**Arquivo Histórico:** [roadmap_archive.md](roadmap_archive.md)

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| Tests | 1571 passing · 18 skipped · 0 failures ✅ |
| Migrations | 77 applied (schema lock v1 + shadow mode v1) ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |
| Phase 9.8 | **COMPLETED** — Resilience & Operational Hub ✅ |
| Phase 10.1 | **COMPLETED** — Schema Lock ✅ |
| Phase 10.2 | **COMPLETED** — WASM Build Validation ✅ |
| Phase 10.3 | **COMPLETED** — Shadow Mode ✅ |

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 20/32 itens de Readiness concluídos.
Verificar checklists detalhados de readiness e testes manuais em [roadmap_archive.md](roadmap_archive.md#milestone-gate-ready-for-first-tenant).

### Checklist "READY FOR FIRST TENANT"

- [x] **Relatório PDF em nível 'Executive Grade'** com Sumário de ROI. ✅
- [x] **Validação rigorosa de CNPJ** (Máscara + Unicidade) em todo o sistema.
- [x] **Função de Reenviar Convite e Arquivamento de Tenants** ativa.
- [x] **Importador de contratos via CSV** com validador de dados. ✅
- [x] **Importador Universal de CSV** funcional com mapeamento persistente por tenant. ✅
- [x] **Relatório PDF em formato de 'Certificado'** com Sumário Executivo. ✅
- [x] **Bot de evidências (Telegram)** integrado à Fila Auditora.
- [x] **Histórico de Meta-Auditoria** ativo para alteração de regras SLA. ✅
- [x] **RLS validada** e testada contra vazamento de dados entre tenants.
- [x] **Fluxo de convite e ativação de conta** para novos administradores funcional.
- [x] **Banco de dados preparado com organization_id** em todas as tabelas transacionais.
- [x] **Tooltips de interface** — `InfoTooltip` global widget criado; campos No-Show e geofence migrados ✅ *(cobertura 100% dos campos complexos pendente de auditoria final)*
- [x] MFA and Edge Proxy active (Total removal of `service_role`) — Edge Proxy ✅ done (9.6.A.1), MFA ✅ done (9.6.A.2).
  - *NOTE: Local MFA validation is currently bypassed in Dev mode when server support is absent. Full end-to-end validation with TOTP enrollment MUST be confirmed in Staging/HMG before production release (INV-6).*
- [x] **Entity Alias Mapping:** Search by Name/CNPJ in `ContractsScreen` and `ContractorManagementScreen` ✅ *(cobertura 100% das telas listadas em 9.8.F — auditoria de telas adicionais pendente)*
- [x] **Accessibility Gate:** Visual contrast validated (WCAG 2.1 AA) for 24/7 operations. ✅
- [x] **Reverse Geocoding:** Functional addresses and zone names instead of raw coordinates in 100% of lists. ✅
- [ ] **Custom RBAC:** Support for basic view isolation between Legal and Financial roles.
- [x] **Audit Log:** Registration of critical changes in SLA models for governance. ✅
- [ ] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing.
- [x] **Sidebar Refactor:** Simplified sidebar (<8 items) with centralized Admin Hub.
- [ ] **Industrial Deep Forms:** Dark theme (Industrial Deep) applied to 100% of form and drawer components.
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.
- [x] **UI Stability:** Refactored SLA modal free of layout bugs and overflow errors.
- [ ] **Financial Guard:** 'Stop-Loss' logic available in contract and penalty setup.
- [ ] **Evidence Snapshot:** Operational rules snapshot integrated into the Evidence Ledger for forensic immutability.
- [ ] ROI Dashboard with Bento Grid and 'Savings BRL' visible.
- [ ] Terms of Use and Privacy Policy (LGPD) integrated into Onboarding.
- [ ] **Invite UX:** Professional invite modal with technical URL masking and "Copy to Clipboard" button.
- [ ] **Self-Service Onboarding:** Tenant creation flow with automated limit configuration.
- [ ] **Evidence Proof:** Functional "Generate Forensic Evidence" button in each verdict.
- [ ] **Legal Gate:** System access block pending specific telemetry LGPD acceptance.
- [x] **Login Localization:** Login screen 100% in PT-BR and free of technical IDs in the visual preview.

---

## Phase 10 — CI/CD & Launch Preparation

### [x] Phase 10.2 — WASM Build Validation

- **Status:** COMPLETED ✅
- **Build:** `flutter build web --wasm` succeeded (193s). `main.dart.wasm` (5.5MB) produced.
- **Dependencies:** All core libs (file_saver, posthog_flutter, drift_flutter, fl_chart, flutter_map) compile cleanly under dart2wasm.
- **CI/CD:**
  - `ci.yml`: Added `wasm-build` job (parallel to test). Artifacts stored for 3 days.
  - `deploy_staging.yml` / `deploy_prod.yml`: Migrated to `--wasm` (timeout 30m).
- **Optimization Note:** Drift OPFS performs best with COOP/COEP headers. Documentation updated for hosting config.
- **Performance:** EvaluationEngine (Pure Dart) benefits directly from near-native arithmetic performance.

### [x] Phase 10.3 — Shadow Mode

- **Status:** COMPLETED ✅
- **Engine:** Parallel `ShadowComparisonService` implemented to validate asynchronous verdicts without blocking the main flow.
- **Deliverables:**
  - `shadow_verdicts` table and Persistence (Postgres & In-Memory).
  - Domain models and repositories for `ShadowVerdict`.
  - Service for automated comparison between simulation and shadow results.
- **Validation:**
  - Comprehensive test suite (1510+ tests total) covering Domain, Application, and Infrastructure layers.
  - **ShadowComparisonServicePostgresTest** added to verify divergence and inhibited logic against real database.
  - Test infrastructure consolidated via `PostgresTestConfig` singleton/cache patterns.
  - SQL Schema migration applied (`20260601000001_shadow_verdicts.sql`).
- **Technical Results:** Comparison logic successfully identifies discrepancies between Evaluation Engine results and persisted state for forensic audit. 80% Critical Divergence threshold validated under actual stress.
- **CI/CD Alignment:** Integration suite enforced in PRs with explicit `services: postgres` support.

### [ ] Phase 10.4 — OCC UX Polish (Differential Refinement)

- **Status:** EM ANDAMENTO — WS-1, WS-2, WS-3, WS-4, WS-5, WS-6 Concluídos ✅
- **Deliverables:**
  - [x] **WS-1: Forensic Authority Language & Sealed Verdict Lock** (Verbs forensicized, 🔒 locked state implemented, Pillar C audit trail active).
  - [x] **WS-2: Predictive SLA Breach Alerts** (Dynamic Risk Buffer + Risk Thermometer visual).
  - [x] **WS-3: Ingestion Health & Confidence Score** (Signal Integrity monitor + Double confirmation logic).
  - [x] **WS-4: Telegram Evidence Bot** (Deno Edge Function + Hot-linking to Verdict Cards).
  - [x] **WS-5: Telemetry Map-Sync** (Reactive repositioning on click).
  - [x] **WS-6: Recurrence & Contractual Context** (Infringement history on cards).
  - [ ] **WS-7: Operational Macros (1-Click Verdict):** (Movido para a Fase 10.8)
  - [ ] **WS-8: Keyboard-First Navigation:** (Movido para a Fase 10.8)
  - [ ] **WS-9: Signal Integrity Monitor:** (Movido para a Fase 10.8)

- Cognitive load audit · Verdict traceable in ≤1 click · WCAG 2.2 AA.
- [x] **[UX] Forensic Audit Context:** Enriquecer o card da Fila Auditora com Histórico de Recorrência (ex: '3ª infração deste veículo/motorista no mês') e visualização comparativa direta entre o dado observado e o limite contratual.
- [x] **[UX] Actionable Verdicts:** Alterar linguagem passiva ('Validar/Rejeitar') para linguagem de autoridade ('Selar Veredito' / 'Recusar Veredito' / 'Solicitar Prova Forense').
- **[BIZ] Telegram Evidence Bot Integration:** Gateway gratuito para motoristas enviarem fotos/provas preventivas diretamente para o card de auditoria via Telegram API (Custo R$ 0).
- **[UX] Invite Link UX Masking:** Replace tokenized raw URLs with a professional invite modal featuring "Copy to Clipboard" and "Access Credential" visual.
- **[BIZ] Contextual Legal Acceptance:** Block first access until Tenant Admin accepts Terms of Use and Privacy Policy (Telemetry-specific).
- **[UX] Predictive SLA Breach Alerts:** Monitoring interface for imminent risk (ETA vs SLA calculation) to allow manager action before contract violation.
- [x] **[UX] Evidence Pan/Zoom Sync:** Implement reactive linking between the telemetry list and the map; clicking an event row must automatically reposition and zoom into the exact point on the map ✅.
- **[UX] Financial Sparklines:** Mini-trend charts (sparklines) in Financial Impact cards for daily volatility visualization.
- **[UX] Data Integrity Drill-down:** Functional links from 'Incomplete Report' alerts to the telemetry Health Dashboard.
- **[UX] Empty State Shortcuts:** Replace "No records" placeholders with quick action cards and contextual onboarding guides.

### [x] Phase 10.4.B — Gate de Ativação do Primeiro Inquilino (MVP de Entrada/Saída)

- **Status:** COMPLETED ✅
- **Deliverables:**
  - [x] **[TECH/UX] Bloco 1: Entrada (Universal CSV Mapping Engine):** Interface de upload (`lib/features/admin/`) que permite ao usuário mapear colunas de arquivos externos para as entidades do sistema (Veículos, Contratos, Zonas) com validação prévia de erros (Pre-flight Validation) antes de gravar no Supabase.
  - [x] **[BIZ/UX] Bloco 2: Saída (Executive-Grade Forensic PDF Certificate):** Geração de dossiê forense (PDF) na camada de aplicação e domínio (concluídos: `ForensicDossier` com `int savingsCents` [INV-4], `IForensicPdfGenerator` e `GenerateForensicDossierHandler` com isolamento de tenant [INV-1] e rastreamento híbrido na cadeia de custódia via `pdf_dossier_logs` append-only).
  - [x] **[UX] Bloco 3: Fechamento de Débitos Críticos do Checklist:**
    - [x] **Accessibility Gate:** Visual contrast validated (WCAG 2.1 AA) for 24/7 operations via `contrast_checker.dart` validations.
    - [x] **Reverse Geocoding:** Endereços legíveis e nomes de zonas em 100% das listas ao invés de coordenadas brutas via `reverse_geocoded_address.dart`.
    - [x] **Audit Log (Meta-Audit):** Registro de alterações críticas nos modelos de SLA para governança via persistência imutável em `sla_template_audit_log`.

### [ ] Phase 10.5 — First Pilot Tenant Onboarding

- Provision tenant · End-to-end validation · PO sign-off.

### [ ] Phase 10.6 — Professional Service & Compliance Finish

*This phase separates simple SaaS clones from a hardened forensic auditing tool.*

- **[BIZ] Executive-Grade 'Audit Certificate' PDF:** (Priorizado para a Fase 10.4.B)
- **[BIZ] Evidence Package (One-Click Dossier):** Função de exportação consolidada contendo Telemetria + Provas Fotográficas + Snapshot do Contrato assinado.
- **[BIZ] Tenant Lifecycle Management:** Funções de 'Reenviar Convite', 'Editar Dados' e 'Arquivar Tenant' (Soft Delete para preservar a Cadeia de Custódia de dados passados).
- **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- **Support Impersonation Security:** "Grant Support Access" button with mandatory audit log and auto-expiry.
- **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).
- **[BIZ] Webhooks & API-First Integration:** Anticipated from Phase 11. Implement 'Sealed Verdict' Webhooks (JSON) for immediate SAP/Oracle/ERP integration.
- **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.
- [ ] **[BIZ] Immutable Rule Snapshot:** No momento do veredito, persistir o snapshot JSON da regra de SLA aplicada para garantir integridade jurídica retroativa.
- [ ] **[BIZ] Executive PDF Certificate:** (Priorizado para a Fase 10.4.B)

### [ ] Phase 10.7 — Operational Automation & Data Ingestion

- [ ] **[TECH] Universal CSV Mapping Engine:** (Priorizado para a Fase 10.4.B)
- [ ] **[UX] Smart Defaulting:** Sistema de preenchimento inteligente de formulários baseado nos últimos registros inseridos (Redução de 60% no tempo de cadastro).
- [ ] **[UX] Bulk Action Mode:** Seleção múltipla de infrações na Fila Auditora para tratamento em massa (Batch Processing).

### [ ] Phase 10.8 — Governance & Dispute

- [ ] **WS-7: Operational Macros (1-Click Verdict):** Atalhos para vereditos comuns (ex: 'Blitz', 'Trânsito') que preenchem justificativa e aplicam regras de tolerância automaticamente. (Pausado da Fase 10.4)
- [ ] **WS-8: Keyboard-First Navigation:** Implementar atalhos de teclado para navegação ultra-rápida na Fila Auditora (Focus Management entre cards). (Pausado da Fase 10.4)
- [ ] **WS-9: Signal Integrity Monitor:** Lógica SQL/Dart para detectar 'GPS Jumps' e inconsistências na telemetria, gerando um 'Confidence Score' no card. (Pausado da Fase 10.4)
- [ ] **[BIZ] Forensic Dispute Portal (ReadOnly):** Tela externa (link temporário/tokenizado) para que transportadores visualizem as evidências contra eles sem precisar de login no sistema core.
- [ ] **[BIZ] Real-time Risk Thermometer:** Visualização preditiva de quebra de SLA (ETA vs Prazo do Contrato) para ação preventiva do operador.
- **[BIZ] SLA Versioning & Lifecycle:** Version control system for SLA models with mandatory effective dates and retirement workflows.
- **[UX] Auditor Productivity Dashboard:** Transform the 'Auditee Queue' into a performance center with metrics for response time, verdict accuracy, and daily throughput.

### [ ] Phase 10.9 — Operational Intelligence & Decision

*Hardening the product against real-world operational challenges and financial disputes.*

- **[BIZ] Bulk Contract Importer (CSV):** Implementar motor de carga em massa para contratos com etapa de Pre-flight Validation (exibe erros de formatação antes de gravar no banco).
- **[BIZ] Human Verdict Affirmation:** Add 'Affirm Violation' (Seals Hash) or 'Inhibit Violation' (Mandatory comment) action buttons directly on the audit detail screen.
- **[BIZ] Progressive Penalty Engine (INV-28):** Support for time-scaled fines that increase based on infringement duration.
- **[BIZ] Penalty Stop-Loss Cap:** Maximum penalty limit field per event for legal and financial risk protection.
- **[BIZ] Immutable Rule Snapshot:** Linking the 'exact version' of SLA rules to the verdict at the time of infringement to shield evidence.
- **[BIZ] SLA Sandbox (ROI Simulator):** Lógica em SQL/Edge Functions para simular 'E se...' (What-if analysis) rodando novos modelos de SLA contra dados históricos para provar economia financeira.
- **[BIZ] Carrier Performance Ranking:** Dashboard de 'Leaderboard' que classifica transportadores por índice de violações e conformidade contratual.
- **[BIZ] Ingestion Health Monitor:** Real-time data integrity dashboard to detect telemetry gaps and hardware failures.
- **[BIZ] Digital Audit Acknowledgement:** Carrier/driver fine acceptance workflow to accelerate billing cycles.
- **[BIZ] One-Click Evidence Package:** Instant forensic dossier generator (Map + Telemetry + Hash + Contract) in PDF for defense against undue fines.
- **[BIZ] Partner Billing Reconciliation:** Invoice crossing tool (CSV Upload) against the immutable Ledger for identifying billing discrepancies.
- **[BIZ] Forensic Dispute Portal:** Limited external interface for carriers/drivers to view evidence snapshots and submit digital counter-proofs.
- **[BIZ] SLA Sensitivity Analysis:** Financial prediction tool based on historical data to simulate the impact of new SLA rules on past performance.

### [ ] Phase 10.10 — High-Stakes Governance & Performance

*Advanced features for large-scale operations and high-precision auditing.*

---

### [ ] Phase 10.11 — Enterprise Governance & Anti-Fraud

*Hardening the platform for multi-national corporations and high-stakes auditing integrity.*

- **[BIZ] Multi-Level Org Hierarchy:** Sub-tenant structure for large corporations (HQ > Branch > Cost Center) with rule inheritance and data isolation.
- **[BIZ] Immutable Admin Log (Meta-Audit):** Implementar tabela de auditoria de sistema (Meta-Audit) para registrar quem alterou regras de SLA e configurações críticas, blindando o sistema contra fraude interna.
- **[BIZ] Configuration Audit Log:** Immutable meta-audit of changes to SLA models, contracts, and permissions (Who changed the rule and when?).
- **[BIZ] Rule-Version Snapshot:** Mecanismo que vincula a 'fotografia' exata da regra de SLA ao veredito no momento da infração, garantindo proteção jurídica retroativa.
- **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).

---

## UI/UX General Polish

- [ ] **Empty State UX:** Substituir placeholders 'Nenhum registro' por guias contextuais (Empty State Onboarding).
- [ ] **Skeletal Loading:** Implementar Shimmer Effect em 100% das listas para melhorar a percepção de performance.

---

## Technical Debt & Maintenance

- **[TECH] Batch RPC Schema Sync:** `batch_update_vehicles` e `batch_update_contracts` (migration `20260412000004`) são funções hardcoded. Ao adicionar colunas atualizáveis a `vehicles` ou `contracts`, adicionar a linha `COALESCE` correspondente nas funções. Backlog: substituir por script de geração estática em CI/CD (evita risco de PL/pgSQL dinâmico e conflitos de placeholders `format()` vs `RAISE`).

---

## Phase 11+ — VeraProb Enterprise: Scale & Integrations

API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.
