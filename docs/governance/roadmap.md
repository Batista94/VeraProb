# VeraProb — Active Strategic Roadmap

**Current Status:** Phase 10.7 entregue (Sealed Verdict Webhook engine & UI Tenant Admin) · **Global UI/UX Overhaul (`happy-rain` P1-P6) concluído** (adoção de tokens VeraProbColors/Typography/Radii/Breakpoints, eliminação de literais na UI, unificação de EmptyState e correção de breakpoints de Stepper) · [NEXT: trilha de notificação Resend na resolução]

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| DB Tests (pgTAP) | 1459+ passing · 130 files · `make test-db` ✅ |
| Migrations | 331 committed ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |
| CI Regression | Zero-Trust Data Masking & Retract State Leak → resolvido por `20260901000004` ✅ |

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 4 itens de Readiness pendentes.

### Checklist "READY FOR FIRST TENANT" (Pending)

- [ ] **Custom RBAC (Dynamic Tenant Roles):** A arquitetura deve permitir que o **Tenant Admin** (Administrador da Organização cliente) crie "Perfis de Acesso" customizados via UI e defina quais telas/KPIs cada perfil pode ver (ex: isolar a visão do Dashboard Financeiro de operadores logísticos comuns). O SuperAdmin do VeraProb apenas gerencia os Tenants e os Tenant Admins, não os perfis internos do cliente.
- [ ] **Financial Guard (Penalty Stop-Loss Cap):** Obrigatório para evitar que falhas de telemetria gerem faturamento infinito (limite de teto de multa por evento/contrato).
- [ ] **Legal Gate & Terms of Use (LGPD):** Bloqueio de acesso ao sistema/telemetria pendente de aceite explícito do contrato de custódia de dados.
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.

---

## Phase 10 — CI/CD & Launch Preparation

### Phase 10.7 — Enterprise Integration & Event Dispatch (Pendente)

- [/] **Notificação/webhook na resolução:** Edge fn `notify-sla-breach` (Comp 5.1) entregue para disparo de breach. Falta o gancho de notificação ao contratante *na resolução* da disputa (Resend/PostHog) — transparência + reduz re-contestação.
- [ ] **[BIZ] Data Extract & Reporting API:** Criação de endpoints de exportação de dados agregados (CSV/JSON) e chaves de API Read-Only para que o C-Level do cliente possa conectar seus painéis do PowerBI diretamente às Views de ROI (`v_roi_summary`) e `contractual_financial_snapshot`.

### Phase 10.8 — Shadow Processing & ROI Proving

- [ ] **SLA Sandbox (ROI Simulator):** Lógica em SQL/Edge Functions para simular 'E se...' (What-if analysis) rodando novos modelos de SLA contra dados históricos para provar economia financeira.
- [ ] **[BIZ] SLA Sensitivity Analysis:** Financial prediction tool based on historical data to simulate the impact of new SLA rules on past performance. *(MOVIDO → Fase 10.8 — fundir com SLA Sandbox; design `simulate_rule_sensitivity` arquivado como fundação.)*

### Phase 10.9 — Governance, Legal & Anti-Fraud (Pendente)

- [/] **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.
- [ ] **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).
- [ ] **[BIZ] Progressive Penalty Engine (INV-28):** Support for time-scaled fines that increase based on infringement duration.
- [ ] **[BIZ] Multi-Level Org Hierarchy:** Sub-tenant structure for large corporations (HQ > Branch > Cost Center) with rule inheritance and data isolation.
- [ ] **[BIZ] Partner Billing Reconciliation:** Invoice crossing tool (CSV Upload) against the immutable Ledger for identifying billing discrepancies.
- [ ] **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- [ ] **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).

### Phase 10.10 — Bulk Operations & Convenience (Conveniência e Ações em Massa)

- [ ] **[UX] Auditor Productivity Dashboard:** Transform the 'Auditee Queue' into a performance center with metrics for response time, verdict accuracy, and daily throughput. *(DIFERIDO pós-first-tenant — precisa de volume real de fila; 10.10 bulk-resolve é a maior alavanca para a mesma persona.)*
- [ ] **[BIZ] Rule Update Consent Flow (Contractor Sign-off):** Implementar fluxo de consentimento/aceite digital por parte da transportadora quando regras ou penalidades de SLA forem alteradas ou renegociadas no Rule Studio, mitigando riscos de alegações de alteração unilateral de regras em auditorias futures.
- [ ] **[UX] Bulk Action Mode:** Seleção múltipla de infrações na Fila Auditora para tratamento em massa (Batch Processing).
- [ ] **WS-7: Operational Macros (1-Click Verdict):** Atalhos para vereditos comuns (ex: 'Blitz', 'Trânsito') que preenchem justificativa e aplicam regras de tolerância automaticamente.
- [ ] **Resolução em lote + filtros:** Auditor com fila grande precisa de bulk-resolve e filtros (clausula/veículo/contrato/valor) na aba Concluídos — reduz custo operacional (margem do cliente final).

---

## UI/UX General Polish [CONCLUÍDO]

- [x] **Empty State UX:** Substituir placeholders 'Nenhum registro' por guias contextuais (Empty State Onboarding) através da unificação com o componente global `EmptyState` (Fase P6).
- [x] **Skeletal Loading:** Implementar Shimmer Effect / Skeletons nas listas para melhorar a percepção de performance.

---

## Technical Debt & Maintenance

- **[TECH] Batch RPC Schema Sync:** `batch_update_vehicles` e `batch_update_contracts` (migration `20260412000004`) são funções hardcoded. Ao adicionar colunas atualizáveis a `vehicles` ou `contracts`, adicionar a linha `COALESCE` correspondente nas funções. Backlog: substituir por script de geração estática em CI/CD (evita risco de PL/pgSQL dinâmico e conflitos de placeholders `format()` vs `RAISE`).

---

## Phase 11+ — VeraProb Enterprise: Scale & Integrations

API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.

- [ ] **[BIZ] Bulk SLA Rule Importer (CSV):** Implementar funcionalidade de importação em massa para parâmetros de regras de SLA vinculadas a contratos (multas, limites de tolerância), evitando a necessidade de cadastro manual individual pós-importação de contratos.
- [ ] **[BIZ] Bulk Contract Importer (CSV):** Implementar motor de carga em massa para contratos com etapa de Pre-flight Validation (exibe erros de formatação antes de gravar no banco).
- [ ] **WS-8: Keyboard-First Navigation:** Implementar atalhos de teclado para navegação ultra-rápida na Fila Auditora (Focus Management entre cards).
- [ ] **[UX] Smart Defaulting:** Sistema de preenchimento inteligente de formulários baseado nos últimos registros inseridos (Redução de 60% no tempo de cadastro).
- [ ] **SuperAdmin Provisioning Script:** Desenvolvimento de script robusto de provisionamento automatizado (`make seed-enterprise`) para instanciar um Tenant isolado contendo volume real de veículos, contratos, zonas e telemetria pré-calculada para fins de demonstração de portfólio.
