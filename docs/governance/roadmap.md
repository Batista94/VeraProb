# VeraProb — Active Strategic Roadmap

**Revision:** 2026-03-26
**Current Status:** Phase 9 in progress (9.6 pending · 9.7 partial ✅) · Phase 10.1 COMPLETED — Target Milestone: **READY FOR FIRST TENANT**
**Arquivo Histórico:** [roadmap_archive.md](roadmap_archive.md)

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| Tests | 1059 passing · 18 skipped · 0 failures ✅ |
| Migrations | 74 applied (schema lock v1 + kinematic guard trigger) ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |
| Phase 10.1 | **COMPLETED** — Schema Lock ✅ |

---

## Phase 9 — VeraProb: De Protótipo de Engenharia a Produto B2B Operacional

> [!CAUTION]
> **CRITICAL SECURITY BLOCKER (PHASE 9.8)**: O sistema contém a `service_role` key no bundle Flutter. **NÃO DEPLOYAR EM PRODUÇÃO** até migração para Edge Proxy.

### [x] Phase 9.5 — Vínculo Dinâmico & UX do Operador ✅ CONCLUÍDA

- **SLA Template Library:** Galeria de modelos pré-configurados (Fretamento, Carga Seca, etc.).
- **Smart Defaults (SQL-based):** Preenchimento preditivo baseado em Heurísticas históricos.
- **ServiceManifest:** Desacoplamento lógico entre ativos e obrigações contratuais.

### [ ] Phase 9.6 — Security & Data Foundation (The Shield)

- **[CRITICAL] Edge Proxy Migration:** Removal of `service_role` from frontend and full migration to Edge Functions.
- **Entity Alias Mapping (UX):** Global translation layer from UUIDs to friendly names (Plates, Drivers, Customers) in the UI.
- **Privileged Access:** MFA for SuperAdmin and JWT Circuit Breakers.
- **[UX] Full Login Localization (PT-BR) & Alias Preview:** Full localization and removal of technical IDs from visual preview on the login screen.
- **[UX] WCAG Contrast Overhaul:** Raise global luminosity of secondary texts (e.g., from Zinc-600 to Zinc-400) to ensure readability in high-luminosity OCC environments.
- **[BIZ] Advanced Custom RBAC:** Granular permissions engine for custom roles (Legal/Finance/Operations) to isolate sensitive UI views (e.g., Financial sees R$, Legal sees Verdicts).
- **[UX] Coordinate Masking (Reverse Geocoding):** UI translation layer to replace raw Lat/Long coordinates with registered zone names or friendly addresses in all operational screens.
- **WASM Build Hygiene:** Rigorous validation of `flutter build web --wasm`.
- **Justified Impersonation:** Support logs with mandatory Ticket ID.

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

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 8/19 itens de Readiness concluídos.
Verificar checklists detalhados de readiness e testes manuais em [roadmap_archive.md](roadmap_archive.md#milestone-gate-ready-for-first-tenant).

### Checklist "READY FOR FIRST TENANT"

- [ ] MFA and Edge Proxy active (Total removal of `service_role`).
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

- **Cryptographic Evidence Export (PDF):** Infringement reports in PDF containing SHA-256 Hash (INV-23) visible in footer for legal validity.
- **Tenant Brand Identity:** Logo upload and primary color definition for exported reports (Basic white-label for credibility).
- **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- **Support Impersonation Security:** "Grant Support Access" button with mandatory audit log and auto-expiry.
- **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).
- **[BIZ] Webhooks & API-First Integration:** Anticipated from Phase 11. Implement 'Sealed Verdict' Webhooks (JSON) for immediate SAP/Oracle/ERP integration.
- **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.

### [ ] Phase 10.7 — Operational Intelligence & Decision

*Hardening the product against real-world operational challenges and financial disputes.*

- **[BIZ] Human Verdict Affirmation:** Add 'Affirm Violation' (Seals Hash) or 'Inhibit Violation' (Mandatory comment) action buttons directly on the audit detail screen.
- **[BIZ] Progressive Penalty Engine (INV-28):** Support for time-scaled fines that increase based on infringement duration.
- **[BIZ] Penalty Stop-Loss Cap:** Maximum penalty limit field per event for legal and financial risk protection.
- **[BIZ] Immutable Rule Snapshot:** Linking the 'exact version' of SLA rules to the verdict at the time of infringement to shield evidence.
- **[BIZ] SLA Sandbox Simulator:** 'What-if' simulation tool in the SLA Model Library to predict financial impact of contractual rule changes.
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
- **[BIZ] Configuration Audit Log:** Immutable meta-audit of changes to SLA models, contracts, and permissions (Who changed the rule and when?).
- **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).

---

## Phase 11+ — VeraProb Enterprise: Scale & Integrations

API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.
