# VeraProb — Active Strategic Roadmap

**Revision:** 2026-06-01
**Current Status:** Phase 10.4.C (In Progress) · [NEXT: Phase 10.4.C — Forensic Evidence UI Integration]

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| Tests | 1571 passing · 18 skipped · 0 failures ✅ |
| Migrations | 227 applied ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 12 itens de Readiness pendentes.

### Checklist "READY FOR FIRST TENANT" (Pending)

- [ ] **Custom RBAC:** Support for basic view isolation between Legal and Financial roles.
- [ ] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing.
- [ ] **Industrial Deep Forms:** Dark theme (Industrial Deep) applied to 100% of form and drawer components.
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.
- [ ] **Financial Guard:** 'Stop-Loss' logic available in contract and penalty setup.
- [ ] ROI Dashboard with Bento Grid and 'Savings BRL' visible.
- [ ] Terms of Use and Privacy Policy (LGPD) integrated into Onboarding.
- [ ] **Self-Service Onboarding:** Tenant creation flow with automated limit configuration.
- [ ] **Evidence Proof:** Functional "Generate Forensic Evidence" button in each verdict.
- [ ] **Legal Gate:** System access block pending specific telemetry LGPD acceptance.

---

## Phase 10 — CI/CD & Launch Preparation

### [/] Phase 10.4.C — Forensic Evidence Snapshot & Immutability
- [x] **[BACKEND] Snapshot Persistence:** Persistência de um snapshot JSON imutável da regra de SLA exata e assinatura digital no momento em que um veredito é selado.
- [ ] **[UX/UI] Evidence Audit Modal:** Exibição do snapshot em modo Read-Only na Fila Auditora para vereditos com status [🔒 Selado] e verificação visual do selo de integridade (Hash Match).

### [ ] Phase 10.5 — Bulk SLA & Contractor Consent Flow

- [ ] **[BIZ] Bulk SLA Rule Importer (CSV):** Implementar funcionalidade de importação em massa para parâmetros de regras de SLA vinculadas a contratos (multas, limites de tolerância), evitando a necessidade de cadastro manual individual pós-importação de contratos.
- [ ] **[BIZ] Rule Update Consent Flow (Contractor Sign-off):** Implementar fluxo de consentimento/aceite digital por parte da transportadora quando regras ou penalidades de SLA forem alteradas ou renegociadas no Rule Studio, mitigando riscos de alegações de alteração unilateral de regras em auditorias futuras.

### [ ] Phase 10.6 — Professional Service & Compliance Finish

*This phase separates simple SaaS clones from a hardened forensic auditing tool.*

- [ ] **[BIZ] Evidence Package (One-Click Dossier):** Função de exportação consolidada contendo Telemetria + Provas Fotográficas + Snapshot do Contrato assinado.
- [ ] **[BIZ] Tenant Lifecycle Management:** Funções de 'Reenviar Convite', 'Editar Dados' e 'Arquivar Tenant' (Soft Delete para preservar a Cadeia de Custódia de dados passados).
- [ ] **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- [ ] **Support Impersonation Security:** "Grant Support Access" button with mandatory audit log and auto-expiry.
- [ ] **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).
- [ ] **[BIZ] Webhooks & API-First Integration:** Anticipated from Phase 11. Implement 'Sealed Verdict' Webhooks (JSON) for immediate SAP/Oracle/ERP integration.
- [ ] **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.

### [ ] Phase 10.7 — Operational Automation & Data Ingestion

- [ ] **[UX] Smart Defaulting:** Sistema de preenchimento inteligente de formulários baseado nos últimos registros inseridos (Redução de 60% no tempo de cadastro).
- [ ] **[UX] Bulk Action Mode:** Seleção múltipla de infrações na Fila Auditora para tratamento em massa (Batch Processing).

### [ ] Phase 10.8 — Governance & Dispute

- [ ] **WS-7: Operational Macros (1-Click Verdict):** Atalhos para vereditos comuns (ex: 'Blitz', 'Trânsito') que preenchem justificativa e aplicam regras de tolerância automaticamente. (Pausado da Fase 10.4)
- [ ] **WS-8: Keyboard-First Navigation:** Implementar atalhos de teclado para navegação ultra-rápida na Fila Auditora (Focus Management entre cards). (Pausado da Fase 10.4)
- [ ] **WS-9: Signal Integrity Monitor:** Lógica SQL/Dart para detectar 'GPS Jumps' e inconsistências na telemetria, gerando um 'Confidence Score' no card. (Pausado da Fase 10.4)
- [ ] **[BIZ] Forensic Dispute Portal (ReadOnly):** Tela externa (link temporário/tokenizado) para que transportadores visualizem as evidências contra eles sem precisar de login no sistema core.
- [ ] **[BIZ] Real-time Risk Thermometer:** Visualização preditiva de quebra de SLA (ETA vs Prazo do Contrato) para ação preventiva do operador.
- [ ] **[BIZ] SLA Versioning & Lifecycle:** Version control system for SLA models with mandatory effective dates and retirement workflows.
- [ ] **[UX] Auditor Productivity Dashboard:** Transform the 'Auditee Queue' into a performance center with metrics for response time, verdict accuracy, and daily throughput.

### [ ] Phase 10.9 — Operational Intelligence & Decision

*Hardening the product against real-world operational challenges and financial disputes.*

- [ ] **[BIZ] Bulk Contract Importer (CSV):** Implementar motor de carga em massa para contratos com etapa de Pre-flight Validation (exibe erros de formatação antes de gravar no banco).
- [ ] **[BIZ] Human Verdict Affirmation:** Add 'Affirm Violation' (Seals Hash) or 'Inhibit Violation' (Mandatory comment) action buttons directly on the audit detail screen.
- [ ] **[BIZ] Progressive Penalty Engine (INV-28):** Support for time-scaled fines that increase based on infringement duration.
- [ ] **[BIZ] Penalty Stop-Loss Cap:** Maximum penalty limit field per event for legal and financial risk protection.
- [ ] **[BIZ] SLA Sandbox (ROI Simulator):** Lógica em SQL/Edge Functions para simular 'E se...' (What-if analysis) rodando novos modelos de SLA contra dados históricos para provar economia financeira.
- [ ] **[BIZ] Carrier Performance Ranking:** Dashboard de 'Leaderboard' que classifica transportadores por índice de violações e conformidade contratual.
- [ ] **[BIZ] Ingestion Health Monitor:** Real-time data integrity dashboard to detect telemetry gaps and hardware failures.
- [ ] **[BIZ] Digital Audit Acknowledgement:** Carrier/driver fine acceptance workflow to accelerate billing cycles.
- [ ] **[BIZ] One-Click Evidence Package:** Instant forensic dossier generator (Map + Telemetry + Hash + Contract) in PDF for defense against undue fines.
- [ ] **[BIZ] Partner Billing Reconciliation:** Invoice crossing tool (CSV Upload) against the immutable Ledger for identifying billing discrepancies.
- [ ] **[BIZ] Forensic Dispute Portal:** Limited external interface for carriers/drivers to view evidence snapshots and submit digital counter-proofs.
- [ ] **[BIZ] SLA Sensitivity Analysis:** Financial prediction tool based on historical data to simulate the impact of new SLA rules on past performance.
- [ ] **[UX] Financial Sparklines:** Mini-trend charts (sparklines) in Financial Impact cards for daily volatility visualization. (Movido da Fase 10.4)
- [ ] **[UX] Data Integrity Drill-down:** Functional links from 'Incomplete Report' alerts to the telemetry Health Dashboard. (Movido da Fase 10.4)

### [ ] Phase 10.10 — High-Stakes Governance & Performance

*Advanced features for large-scale operations and high-precision auditing.*

---

### [ ] Phase 10.11 — Enterprise Governance & Anti-Fraud

*Hardening the platform for multi-national corporations and high-stakes auditing integrity.*

- [ ] **[BIZ] Multi-Level Org Hierarchy:** Sub-tenant structure for large corporations (HQ > Branch > Cost Center) with rule inheritance and data isolation.
- [ ] **[BIZ] Immutable Admin Log (Meta-Audit):** Implementar tabela de auditoria de sistema (Meta-Audit) para registrar quem alterou regras de SLA e configurações críticas, blindando o sistema contra fraude interna.
- [ ] **[BIZ] Configuration Audit Log:** Immutable meta-audit of changes to SLA models, contracts, and permissions (Who changed the rule and when?).
- [ ] **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).

### [ ] Phase 10.12 — Automated Enterprise Showcase (Seed & Provisioning)

- Desenvolvimento de script robusto de provisionamento automatizado (`make seed-enterprise`) para instanciar um Tenant isolado contendo volume real de veículos, contratos, zonas e telemetria pré-calculada para fins de demonstração de portfólio.

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
