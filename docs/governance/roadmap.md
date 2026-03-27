# VeraProb — Active Strategic Roadmap

**Revision:** 2026-03-26
**Current Status:** Phase 9.7 — Core Forensic Intelligence (The Brain) · [READY FOR FIRST TENANT](docs/governance/roadmap.md#milestone-gate-ready-for-first-tenant)
**Arquivo Histórico:** [roadmap_archive.md](roadmap_archive.md)

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| Tests | 1048 passing (+6 new MFA tests) · 23 skipped · 0 failures ✅ |
| Migrations | 74 applied (schema lock v1 + kinematic guard trigger) ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |
| Phase 10.1 | **COMPLETED** — Schema Lock ✅ |

---

### [ ] Phase 9.7 — Core Forensic Intelligence (The Brain) · PARTIAL ✅

- **[x] Kinematic Guard (INV-17):** ✅ Physical validation ($v = \Delta d / \Delta t$) — domain service + DB trigger (`vp_kinematic_guard`) on `canonical_facts`. Flags `KINEMATIC_ANOMALY`. Full TDD coverage (8 tests).
- **[x] Heurísticas de Alerta:** ✅ `AlertFinancialImpact` VO + `AlertImpactCalculator` — real-time R$ impact for delay, no-show, kinematic anomaly. Severity tiers (low/medium/high/critical).
- **[x] GeoMath Consolidation:** ✅ `haversineMeters()` / `impliedSpeedCms()` centralized in `lib/core/utils/geo_math.dart`.
- **[ ] Visual Evidence Snapshots:** Generation of mini-map with geofence overlay in audit cards.
- **[ ] [UX] SLA Creation Wizard:** Refactor 'New SLA Model' modal into stepped interface (Wizard) to eliminate layout bugs.
- **[ ] [UX] SLA Parameter Grouping:** Logical grouping of fields by category (Temporal, Behavioral, Financial) to reduce cognitive load.
- **[ ] [UX] Side Drawer Dark Sync:** Unify registration drawers (e.g., Drivers) with the Industrial Deep Theme to prevent visual fatigue.
- **[ ] Industrial Deep Theme:** Interface in Slate/Zinc tones to reduce visual fatigue 24/7.

### [ ] Phase 9.8 — Resilience & Operational Hub (The Body)

- **[UX] Sidebar Hub Refactor:** Consolidate setup menus into the Admin Hub, reducing the operational sidebar (<8 items).
- **Background Sync Resilience:** Local SQLite buffer to ensure Chain of Custody in zones without signal.
- **Driver Defense Portal:** Interface for submitting preventive justifications (photos/proofs) linked to audit.
- **Heartbeat Monitor:** Logic to differentiate hardware sabotage from network failures.
- **Late-Arrival Window Protocol (INV-12):** 48-hour window for deterministic reprocessing.
- **Hard Quota Enforcement:** Database triggers for `max_vehicles` and `max_contracts` limits.
- **[BIZ] Predictive Tenant Provisioning:** SuperAdmin Wizard logic for auto-filling limits based on Selected Plan.
- **[UX] Login Split-Screen Refactor:** Transition to split-screen (40/60) Desktop layout to establish Forensic Authority.
- **[UX] Smart CNPJ Protocol:** Implementar máscara dinâmica (00.000.000/0000-00), trava de unicidade no banco (Unique Constraint) e validação de dígito verificador.
- **[UX] Global Info Tooltips:** Substituição de descrições extensas por ícones de informação flutuantes para reduzir a carga cognitiva do operador e limpeza visual.
- **[UX] Searchable Entity Mapping:** Unificar a lógica de busca/filtro por Nome e CNPJ no cadastro de contratos e tenants.
- **[UX] Universal CSV Importer (Bootstrap Edition):** Interface de mapeamento dinâmico de colunas para ingestão de qualquer rastreador sem necessidade de código customizado por tenant.
- **[UX] Smart Contextual Geocoding:** Camada de tradução de coordenadas usando OpenStreetMap (Nominatim) + Queries Espaciais no banco para exibir nomes de zonas e endereços humanos em vez de Lat/Long.
- **[BIZ] Manual CSV Importer (V1):** Interface básica para upload e mapeamento manual de colunas de telemetria para validação do motor.
- **[BIZ] Tenant Admin Invitations:** Sistema de convites via e-mail (Resend) para o primeiro acesso de gestores de empresas.

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 8/19 itens de Readiness concluídos.
Verificar checklists detalhados de readiness e testes manuais em [roadmap_archive.md](roadmap_archive.md#milestone-gate-ready-for-first-tenant).

### Checklist "READY FOR FIRST TENANT"

- [ ] **Relatório PDF em nível 'Executive Grade'** com Sumário de ROI.
- [ ] **Validação rigorosa de CNPJ** (Máscara + Unicidade) em todo o sistema.
- [ ] **Função de Reenviar Convite e Arquivamento de Tenants** ativa.
- [ ] **Importador de contratos via CSV** com validador de dados.
- [ ] **Importador Universal de CSV** funcional com mapeamento persistente por tenant.
- [ ] **Relatório PDF em formato de 'Certificado'** com Sumário Executivo.
- [ ] **Bot de evidências (Telegram)** integrado à Fila Auditora.
- [ ] **Histórico de Meta-Auditoria** ativo para alteração de regras SLA.
- [ ] **RLS validada** e testada contra vazamento de dados entre tenants.
- [ ] **Fluxo de convite e ativação de conta** para novos administradores funcional.
- [ ] **Banco de dados preparado com organization_id** em todas as tabelas transacionais.
- [ ] **Tooltips de interface** aplicados em 100% dos campos complexos.
- [x] MFA and Edge Proxy active (Total removal of `service_role`) — Edge Proxy ✅ done (9.6.A.1), MFA ✅ done (9.6.A.2).
  - *NOTE: Local MFA validation is currently bypassed in Dev mode when server support is absent. Full end-to-end validation with TOTP enrollment MUST be confirmed in Staging/HMG before production release (INV-6).*
- [ ] Entity Alias Mapping implemented in 100% of operational screens.
- [ ] **Accessibility Gate:** Visual contrast validated (WCAG 2.1 AA) for 24/7 operations.
- [ ] **Reverse Geocoding:** Functional addresses and zone names instead of raw coordinates in 100% of lists.
- [ ] **Custom RBAC:** Support for basic view isolation between Legal and Financial roles.
- [ ] **Audit Log:** Registration of critical changes in SLA models for governance.
- [ ] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing.
- [ ] **Sidebar Refactor:** Simplified sidebar (<8 items) with centralized Admin Hub.
- [ ] **Industrial Deep Forms:** Dark theme (Industrial Deep) applied to 100% of form and drawer components.
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.
- [ ] **UI Stability:** Refactored SLA modal free of layout bugs and overflow errors.
- [ ] **Financial Guard:** 'Stop-Loss' logic available in contract and penalty setup.
- [ ] **Evidence Snapshot:** Operational rules snapshot integrated into the Evidence Ledger for forensic immutability.
- [ ] ROI Dashboard with Bento Grid and 'Savings BRL' visible.
- [ ] Terms of Use and Privacy Policy (LGPD) integrated into Onboarding.
- [ ] **Invite UX:** Professional invite modal with technical URL masking and "Copy to Clipboard" button.
- [ ] **Self-Service Onboarding:** Tenant creation flow with automated limit configuration.
- [ ] **Evidence Proof:** Functional "Generate Forensic Evidence" button in each verdict.
- [ ] **Legal Gate:** System access block pending specific telemetry LGPD acceptance.
- [ ] **Login Localization:** Login screen 100% in PT-BR and free of technical IDs in the visual preview.

---

## Phase 10 — CI/CD & Launch Preparation

### [ ] Phase 10.2 — WASM Build Validation

- Build web sem `dart:html`/`dart:js` · Freezed up-to-date.

### [ ] Phase 10.3 — Shadow Mode

- EvaluationEngine paralelo validado contra fluxos manuais.

### [ ] Phase 10.4 — OCC UX Polish (Diferential Refinement)

- Cognitive load audit · Verdict traceable in ≤1 click · WCAG 2.2 AA.
- **[UX] Forensic Audit Context:** Enriquecer o card da Fila Auditora com Histórico de Recorrência (ex: '3ª infração deste veículo/motorista no mês') e visualização comparativa direta entre o dado observado e o limite contratual.
- **[UX] Actionable Verdicts:** Alterar linguagem passiva ('Validar/Rejeitar') para linguagem de autoridade ('Selar Veredito' / 'Solicitar Mais Provas').
- **[BIZ] Telegram Evidence Bot Integration:** Gateway gratuito para motoristas enviarem fotos/provas preventivas diretamente para o card de auditoria via Telegram API (Custo R$ 0).
- **[UX] Operational Macros (1-Click Verdict):** Atalhos para vereditos comuns (ex: 'Blitz Policial', 'Parada Autorizada') que preenchem justificativa e anexam regras de tolerância automaticamente.
- **[UX] Ingestion Health Monitor:** Widget de integridade que sinaliza 'Gaps' de sinal ou falhas de hardware antes da geração do relatório final.
- **[UX] Invite Link UX Masking:** Replace tokenized raw URLs with a professional invite modal featuring "Copy to Clipboard" and "Access Credential" visual.
- **[BIZ] Contextual Legal Acceptance:** Block first access until Tenant Admin accepts Terms of Use and Privacy Policy (Telemetry-specific).
- **[UX] Predictive SLA Breach Alerts:** Monitoring interface for imminent risk (ETA vs SLA calculation) to allow manager action before contract violation.
- **[UX] Evidence Pan/Zoom Sync:** Implement reactive linking between the telemetry list and the map; clicking an event row must automatically reposition and zoom into the exact point on the map.
- **[UX] Financial Sparklines:** Mini-trend charts (sparklines) in Financial Impact cards for daily volatility visualization.
- **[UX] Data Integrity Drill-down:** Functional links from 'Incomplete Report' alerts to the telemetry Health Dashboard.
- **[UX] Empty State Shortcuts:** Replace "No records" placeholders with quick action cards and contextual onboarding guides.

### [ ] Phase 10.5 — First Pilot Tenant Onboarding

- Provision tenant · End-to-end validation · PO sign-off.

### [ ] Phase 10.6 — Professional Service & Compliance Finish

*This phase separates simple SaaS clones from a hardened forensic auditing tool.*

- **[BIZ] Executive-Grade 'Audit Certificate' PDF:** Motor de PDF (Dart pdf package) para gerar dossiês com Sumário de ROI, Selo de Autenticidade e Hash SHA-256 (INV-23) em destaque. Refatoração total do exportador de relatórios com Branding do Tenant (Logo/Cores) e remoção de IDs técnicos.
- **[BIZ] Evidence Package (One-Click Dossier):** Função de exportação consolidada contendo Telemetria + Provas Fotográficas + Snapshot do Contrato assinado.
- **[BIZ] Tenant Lifecycle Management:** Funções de 'Reenviar Convite', 'Editar Dados' e 'Arquivar Tenant' (Soft Delete para preservar a Cadeia de Custódia de dados passados).
- **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- **Support Impersonation Security:** "Grant Support Access" button with mandatory audit log and auto-expiry.
- **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).
- **[BIZ] Webhooks & API-First Integration:** Anticipated from Phase 11. Implement 'Sealed Verdict' Webhooks (JSON) for immediate SAP/Oracle/ERP integration.
- **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.

### [ ] Phase 10.7 — Operational Intelligence & Decision

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

---

### [ ] Phase 10.8 — High-Stakes Governance & Performance

*Advanced features for large-scale operations and high-precision auditing.*

- **[BIZ] SLA Versioning & Lifecycle:** Version control system for SLA models with mandatory effective dates and retirement workflows.
- **[UX] Auditor Productivity Dashboard:** Transform the 'Auditee Queue' into a performance center with metrics for response time, verdict accuracy, and daily throughput.

---

### [ ] Phase 10.9 — Enterprise Governance & Anti-Fraud

*Hardening the platform for multi-national corporations and high-stakes auditing integrity.*

- **[BIZ] Multi-Level Org Hierarchy:** Sub-tenant structure for large corporations (HQ > Branch > Cost Center) with rule inheritance and data isolation.
- **[BIZ] Immutable Admin Log (Meta-Audit):** Implementar tabela de auditoria de sistema (Meta-Audit) para registrar quem alterou regras de SLA e configurações críticas, blindando o sistema contra fraude interna.
- **[BIZ] Configuration Audit Log:** Immutable meta-audit of changes to SLA models, contracts, and permissions (Who changed the rule and when?).
- **[BIZ] Rule-Version Snapshot:** Mecanismo que vincula a 'fotografia' exata da regra de SLA ao veredito no momento da infração, garantindo proteção jurídica retroativa.
- **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).

---

## Phase 11+ — VeraProb Enterprise: Scale & Integrations

API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.
