# VeraProb — Active Strategic Roadmap

**Current Status:** Phase 10.7 entregue (Sealed Verdict Webhook engine, UI Tenant Admin & Notificação Resend na resolução) · **Custom RBAC, Financial Guard (Stop-Loss) & Legal Gate (LGPD) concluídos** (com cobertura total de testes pgTAP, integração, widgets e fluxos de consentimento) · **Global UI/UX Overhaul (`happy-rain` P1-P6) concluído**. · **Phase 11 — A portável** incluída no roadmap (missão R11; Etapa −1 PASS documental; Etapa 0 ainda não autorizada neste arquivo).

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| DB Tests (pgTAP) | 1500+ passing · 165 files · `make test-db` ✅ |
| Migrations | 377 committed ✅ (recontado `supabase/migrations/*.sql` em 2026-07-21T19:12:07Z — missão R11) |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |
| CI Regression | Zero-Trust Data Masking & Retract State Leak → resolvido por `20260901000004` ✅ |

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 1 item de Readiness pendente.

### Checklist "READY FOR FIRST TENANT" (Pending)

- [x] **Custom RBAC (Dynamic Tenant Roles):** A arquitetura deve permitir que o **Tenant Admin** (Administrador da Organização cliente) crie "Perfis de Acesso" customizados via UI e defina quais telas/KPIs cada perfil pode ver (ex: isolar a visão do Dashboard Financeiro de operadores logísticos comuns). O SuperAdmin do VeraProb apenas gerencia os Tenants e os Tenant Admins, não os perfis internos do cliente.
- [x] **Financial Guard (Penalty Stop-Loss Cap):** Obrigatório para evitar que falhas de telemetria gerem faturamento infinito (limite de teto de multa por evento/contrato).
- [x] **Legal Gate & Terms of Use (LGPD):** Bloqueio de acesso ao sistema/telemetria pendente de aceite explícito do contrato de custódia de dados.
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.

**Bloqueantes de piloto (Phase 11 — A portável; runtime NOT RUN):** `P-REV-IMPL-01`, `PG-REVOCATION`, `PG-BACKUP`, `PG-RESTORE`, `PG-DR`. Não confundir com o checklist de produto acima.

---

## Phase 10 — CI/CD & Launch Preparation

### Phase 10.7 — Enterprise Integration & Event Dispatch (Pendente)

- [x] **Notificação/webhook na resolução:** Edge fn `notify-sla-breach` (Comp 5.1) para disparo de breach e Edge fn `dispatch-carrier-notifications` integrada ao Resend para notificações automáticas na resolução do veredicto (via `carrier_notification_outbox` e portal da disputa) entregues e testadas.
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

## Phase 11 — A portável

**Direção Accepted (ADR-010):** permanecer em Supabase + Flutter; corrigir portabilidade, revogação e DR antes do primeiro piloto. Go, React, PostgreSQL self-host e migração B/C **não** estão aprovados nem agendados. Reabertura A/B/C somente por gatilhos objetivos + nova decisão formal.

**SSOT:** `docs/governance/proposals/phase11_enterprise_pivot.md` · ADRs 010–013 · inventário / threat model / parity checklist.

| Etapa | Status | Escopo | Proibido nesta etapa |
|-------|--------|--------|----------------------|
| −1 | **PASS** (documental; checkpoint `08fda779`) | Contrato + ADRs Accepted | Código; cutover |
| 0 | **NOT STARTED** (após R11; requer AUTH-E0) | Specs executáveis / governança A portável | Código; Go/React; remoção de regras Flutter/Supabase |
| 1 | Não iniciada | `P-REV-IMPL-01`, backup/restore, drills DR pré-prod | Self-host PG16; Go produtivo |
| 2 | Não iniciada | OpenAPI das superfícies existentes (sem Go produtivo) | Go produtivo sem go/no-go |
| 3 | Não iniciada | Desacoplar repositories Flutter do provedor | React; reescrita UI |
| 4 | Não iniciada | Portabilidade / segurança / restore / gatilhos | Cutover automático |
| Cutover | **Não agendado** | — | Só após decisão B ou C |

### Gates bloqueantes do primeiro piloto (runtime)

| Gate / ID | Estado | Nota |
|-----------|--------|------|
| `P-REV-IMPL-01` | OPEN | Implementação registro PG + wiring Edge/RLS |
| `PG-REVOCATION` | CONTRACT COMPLETE / runtime **NOT RUN** | Não declarar PASS sem evidência |
| `PG-BACKUP` | NOT RUN | Dump diário off-site (+ Storage classificado) |
| `PG-RESTORE` | NOT RUN | Restore exercitado ≤24h |
| `PG-DR` | NOT RUN | Continuity drill; RPO/RTO pré-prod **24h/24h, sem SLA** |

### R11 — mapeamento origem → destino (backlog Phase 11+)

Inclusão de “Phase 11 — A portável” **não** substitui o backlog empresarial preexistente. Itens abaixo preservados **1:1** (mesmo texto e mesmo estado de checkbox); nenhum removido, reclassificado ou marcado concluído.

| Origem (pré-R11) | Destino (pós-R11) | Estado preservado |
|------------------|-------------------|-------------------|
| `Phase 11+` › Bulk SLA Rule Importer (CSV) | `Phase 11+ — backlog futuro (Scale & Integrations)` › mesmo item | `[ ]` |
| `Phase 11+` › Bulk Contract Importer (CSV) | idem › mesmo item | `[ ]` |
| `Phase 11+` › WS-8: Keyboard-First Navigation | idem › mesmo item | `[ ]` |
| `Phase 11+` › Smart Defaulting | idem › mesmo item | `[ ]` |
| `Phase 11+` › SuperAdmin Provisioning Script | idem › mesmo item | `[ ]` |
| Intro “API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.” | idem › mesma intro | preservada |

---

## Phase 11+ — backlog futuro (Scale & Integrations)

> Título histórico: **Phase 11+ — VeraProb Enterprise: Scale & Integrations**. Mantido como backlog futuro sob o programa Phase 11; itens intactos 1:1 (missão R11). Remoção/reclassificação/conclusão exige decisão explícita.

API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.

- [ ] **[BIZ] Bulk SLA Rule Importer (CSV):** Implementar funcionalidade de importação em massa para parâmetros de regras de SLA vinculadas a contratos (multas, limites de tolerância), evitando a necessidade de cadastro manual individual pós-importação de contratos.
- [ ] **[BIZ] Bulk Contract Importer (CSV):** Implementar motor de carga em massa para contratos com etapa de Pre-flight Validation (exibe erros de formatação antes de gravar no banco).
- [ ] **WS-8: Keyboard-First Navigation:** Implementar atalhos de teclado para navegação ultra-rápida na Fila Auditora (Focus Management entre cards).
- [ ] **[UX] Smart Defaulting:** Sistema de preenchimento inteligente de formulários baseado nos últimos registros inseridos (Redução de 60% no tempo de cadastro).
- [ ] **SuperAdmin Provisioning Script:** Desenvolvimento de script robusto de provisionamento automatizado (`make seed-enterprise`) para instanciar um Tenant isolado contendo volume real de veículos, contratos, zonas e telemetria pré-calculada para fins de demonstração de portfólio.
