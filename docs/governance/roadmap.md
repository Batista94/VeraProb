# VeraProb — Active Strategic Roadmap

**Revision:** 2026-06-10
**Current Status:** Phase 10.5 (In Progress) · [NEXT: Phase 10.5 — Core Transactional Integrity]

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| Tests | 1916 passing · 12 skipped · 0 failures ✅ |
| Migrations | 245 applied ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 5 itens de Readiness pendentes.

### Checklist "READY FOR FIRST TENANT" (Pending)

- [ ] **Custom RBAC:** Support for basic view isolation between Legal and Financial roles.
- [ ] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing.
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.
- [ ] **Financial Guard:** 'Stop-Loss' logic available in contract and penalty setup.
- [ ] **Legal Gate:** System access block pending specific telemetry LGPD acceptance.

---

## Phase 10 — CI/CD & Launch Preparation

### [x] Phase 10.4.C — Forensic Evidence Snapshot & Immutability
- [x] **[BACKEND] Snapshot Persistence:** Persistência de um snapshot JSON imutável da regra de SLA exata e assinatura digital no momento em que um veredito é selado.
- [x] **[UX/UI] Evidence Audit Modal:** Exibição do snapshot em modo Read-Only na Fila Auditora para vereditos com status [🔒 Selado] e verificação visual do selo de integridade (Hash Match).

### [ ] Phase 10.5 — Core Transactional Integrity (Prioridade Máxima)

- [x] **Database Transactional Hardening (approve/reject):** Vereditos iniciais (`approve`/`reject`) migrados para os RPCs `approve_sanction`/`reject_sanction` `SECURITY DEFINER` (migração `20260812000001`): `lock (FOR UPDATE)` → re-check `status='pending'` → append no ledger (`VERDICT_SEALED`/`VERDICT_REFUSED`) → flip da fila, tudo em UMA transação. Fecha a corrida TOCTOU que gerava fatos duplicados (INV-3). Hardening máximo: revisor vinculado ao JWT `sub` (anti-spoof), sem grant a `anon`/`service_role`, RBAC server-side (`TENANT_ADMIN`/`AUDITOR`), `42501` idêntico para wrong-org/not-found (INV-26), motivo de rejeição fail-closed. Trilha Dart refatorada para chamada RPC única; PBT de idempotência migrado p/ mecanismo `dbTransactionalRpc`. pgTAP 21/21, `make test-db` 559 PASS, scanner `[GO]`.
- [x] **Atomicidade total (RPC transacional):** Resolução de disputas (`accept`/`overturn`/`retract`) migrada para o RPC `resolve_dispute` `SECURITY DEFINER`: `lock (FOR UPDATE)` → re-check de status → append no ledger → update da fila → (overturn) selo de snapshot inline, tudo em UMA transação. Fecha a corrida TOCTOU (INV-3) e o buraco de não-atomicidade (INV-21). Hardening máximo: rejeita JWT nulo, sem grant a `anon`/`service_role`, RBAC server-side (`TENANT_ADMIN`/`AUDITOR`), `42501` idêntico para wrong-org/not-found (INV-26), índice único parcial por-partição como defesa-em-profundidade (`23505`). Twin-flaw corrigida: `seal_dispute_resolution_snapshot` agora fail-closed em JWT nulo. (approve/reject seguem como dívida pré-existente apontada por QA-Security.)
- [x] **Dual-control (quatro-olhos) em vereditos de alto valor:** Acima de um threshold de `fineCents` (`organizations.dual_control_threshold_cents` + override por contrato; `COALESCE(contract, org)`), o veredito não vira terminal — entra em `pending_peer_review` exigindo um SEGUNDO auditor distinto. Cobre AMBAS direções (ENFORCE `approve`/`overturn` E WAIVE `reject`/`dispute-accept`) — o vetor de conluio real. Migrações `20260812000002` (schema: threshold org+contrato, status `pending_peer_review`, colunas `first_reviewer_id`/`peer_review_*`, novos fatos `PEER_REVIEW_*`) + `20260812000003` (RPCs: `approve`/`reject`/`resolve_dispute` `CREATE OR REPLACE` com branch de threshold; novas `confirm_peer_review`/`decline_peer_review`/`expire_stale_peer_reviews`). **Garantia matemática `reviewer2 != reviewer1`**: tanto `first_reviewer_id` quanto o confirmador derivam do JWT `sub` server-side — mesma pessoa ⇒ mesmo `sub` ⇒ `DualControlSelfApprovalException` (`P0001`); um auditor nunca solicita E confirma. Fato terminal carrega as DUAS assinaturas (trilha dual-signature SOC2). `fine_cents` lido do `verdict_evidence` selado (INV-15: threshold mudar em voo não altera veredito em andamento). TTL/expiry (anti-starvation, `expire_stale_peer_reviews` ator SYSTEM) + decline (qualquer auditor, incl. o requisitante). Domínio: enum `pendingPeerReview` + arcos no guard; handlers `ConfirmPeerReviewHandler`/`DeclinePeerReviewHandler`; UX: lane "Aguardando 2º Auditor" + confirm desabilitado para o requisitante. pgTAP 23/23 (+ schema 12/12), `make test-db` 594 PASS, `flutter analyze` limpo.

### [ ] Phase 10.6 — Forensic Operations & Dispute Reality

- [ ] **[near-term] Anexo de evidência do contratante:** "Aguardando Evidência" pressupõe que o contestante envia prova. Falta o canal de upload (foto/doc/telemetria externa) vinculado por `organization_id` (INV-1) e selado por SHA-256 (INV-9) — o auditor decide *sobre* algo.
- [ ] **[near-term] Taxonomia de motivos (reason codes) vs texto livre:** `rejection_reason`/`resolutionReason` livres dificultam analytics e auditoria. Enum versionado de motivos (ex.: `FORCE_MAJEURE`, `SENSOR_FAULT`, `CONTRACT_EXCEPTION`) + campo livre opcional. Permite relatórios de "por que multas são inibidas".
- [ ] **Trilha de "quem cancelou":** No retract, preservamos `reviewed_by` do disputante; o ledger `DISPUTE_RETRACTED` registra o cancelador. Expor essa cadeia na UI (timeline de estados do card) eleva a explicabilidade (INV-23).
- [ ] **[near-term] SLA-timer de disputa (aging):** Toda disputa tem prazo de resolução (ex.: 5 dias úteis). Dashboard de "disputas vencendo/vencidas" + auto-escalonamento. Hoje uma disputa pode ficar `disputed` indefinidamente.
- [ ] **[BIZ] Forensic Dispute Portal (ReadOnly):** Tela externa (link temporário/tokenizado) para que transportadores visualizem as evidências contra eles sem precisar de login no sistema core.
- [ ] **[BIZ] Forensic Dispute Portal:** Limited external interface for carriers/drivers to view evidence snapshots and submit digital counter-proofs.
- [x] **WS-9: Signal Integrity Monitor:** Lógica SQL/Dart para detectar 'GPS Jumps' e inconsistências na telemetria, gerando um 'Confidence Score' no card. (Pausado da Fase 10.4)
- [ ] **[BIZ] Real-time Risk Thermometer:** Visualização preditiva de quebra de SLA (ETA vs Prazo do Contrato) para ação preventiva do operador.
- [ ] **[BIZ] SLA Versioning & Lifecycle:** Version control system for SLA models with mandatory effective dates and retirement workflows.
- [ ] **[UX] Auditor Productivity Dashboard:** Transform the 'Auditee Queue' into a performance center with metrics for response time, verdict accuracy, and daily throughput.
- [ ] **[BIZ] Human Verdict Affirmation:** Add 'Affirm Violation' (Seals Hash) or 'Inhibit Violation' (Mandatory comment) action buttons directly on the audit detail screen.
- [x] **[BIZ] One-Click Evidence Package:** Instant forensic dossier generator (Map + Telemetry + Hash + Contract) in PDF for defense against undue fines.
- [x] **[BIZ] Evidence Package (One-Click Dossier):** Função de exportação consolidada contendo Telemetria + Provas Fotográficas + Snapshot do Contrato assinado.
- [ ] **[BIZ] Carrier Performance Ranking:** Dashboard de 'Leaderboard' que classifica transportadores por índice de violações e conformidade contratual.
- [ ] **[BIZ] Ingestion Health Monitor:** Real-time data integrity dashboard to detect telemetry gaps and hardware failures.
- [ ] **[BIZ] Digital Audit Acknowledgement:** Carrier/driver fine acceptance workflow to accelerate billing cycles.
- [ ] **[BIZ] SLA Sensitivity Analysis:** Financial prediction tool based on historical data to simulate the impact of new SLA rules on past performance.
- [ ] **[UX] Financial Sparklines:** Mini-trend charts (sparklines) in Financial Impact cards for daily volatility visualization. (Movido da Fase 10.4)
- [ ] **[UX] Data Integrity Drill-down:** Functional links from 'Incomplete Report' alerts to the telemetry Health Dashboard. (Movido da Fase 10.4)

### [ ] Phase 10.7 — Enterprise Integration & Event Dispatch

- [ ] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing.
- [ ] **[BIZ] Webhooks & API-First Integration:** Anticipated from Phase 11. Implement 'Sealed Verdict' Webhooks (JSON) for immediate SAP/Oracle/ERP integration.
- [ ] **Notificação/webhook na resolução:** Resend/PostHog/webhook ao contratante quando disputa é resolvida (transparência + reduz re-contestação). Já há stack Resend disponível.

### [ ] Phase 10.8 — Shadow Processing & ROI Proving

- [ ] **SLA Sandbox (ROI Simulator):** Lógica em SQL/Edge Functions para simular 'E se...' (What-if analysis) rodando novos modelos de SLA contra dados históricos para provar economia financeira.
- [ ] **Financial Guard:** 'Stop-Loss' logic available in contract and penalty setup.
- [ ] **[BIZ] Penalty Stop-Loss Cap:** Maximum penalty limit field per event for legal and financial risk protection.

### [ ] Phase 10.9 — Governance, Legal & Anti-Fraud

- [ ] **Legal Gate:** System access block pending specific telemetry LGPD acceptance.
- [ ] **Terms of Use (LGPD):** Terms of Use and Privacy Policy (LGPD) integrated into Onboarding.
- [ ] **Self-Service Onboarding:** Tenant creation flow with automated limit configuration.
- [ ] **[BIZ] Immutable Admin Log (Meta-Audit):** Implementar tabela de auditoria de sistema (Meta-Audit) para registrar quem alterou regras de SLA e configurações críticas, blindando o sistema contra fraude interna.
- [ ] **[BIZ] Configuration Audit Log:** Immutable meta-audit of changes to SLA models, contracts, and permissions (Who changed the rule and when?).
- [ ] **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).
- [/] **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.
- [x] **[BIZ] Tenant Lifecycle Management:** Funções de 'Reenviar Convite', 'Editar Dados' e 'Arquivar Tenant' (Soft Delete para preservar a Cadeia de Custódia de dados passados).
- [ ] **Support Impersonation Security:** "Grant Support Access" button with mandatory audit log and auto-expiry.
- [ ] **[BIZ] Progressive Penalty Engine (INV-28):** Support for time-scaled fines that increase based on infringement duration.
- [ ] **[BIZ] Multi-Level Org Hierarchy:** Sub-tenant structure for large corporations (HQ > Branch > Cost Center) with rule inheritance and data isolation.
- [ ] **[BIZ] Partner Billing Reconciliation:** Invoice crossing tool (CSV Upload) against the immutable Ledger for identifying billing discrepancies.
- [ ] **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- [ ] **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).

### [ ] Phase 10.10 — Bulk Operations & Convenience (Conveniência e Ações em Massa)

- [ ] **[BIZ] Bulk SLA Rule Importer (CSV):** Implementar funcionalidade de importação em massa para parâmetros de regras de SLA vinculadas a contratos (multas, limites de tolerância), evitando a necessidade de cadastro manual individual pós-importação de contratos.
- [ ] **[BIZ] Rule Update Consent Flow (Contractor Sign-off):** Implementar fluxo de consentimento/aceite digital por parte da transportadora quando regras ou penalidades de SLA forem alteradas ou renegociadas no Rule Studio, mitigando riscos de alegações de alteração unilateral de regras em auditorias futuras.
- [ ] **[BIZ] Bulk Contract Importer (CSV):** Implementar motor de carga em massa para contratos com etapa de Pre-flight Validation (exibe erros de formatação antes de gravar no banco).
- [ ] **[UX] Bulk Action Mode:** Seleção múltipla de infrações na Fila Auditora para tratamento em massa (Batch Processing).
- [ ] **WS-8: Keyboard-First Navigation:** Implementar atalhos de teclado para navegação ultra-rápida na Fila Auditora (Focus Management entre cards).
- [ ] **WS-7: Operational Macros (1-Click Verdict):** Atalhos para vereditos comuns (ex: 'Blitz', 'Trânsito') que preenchem justificativa e aplicam regras de tolerância automaticamente.
- [ ] **Resolução em lote + filtros:** Auditor com fila grande precisa de bulk-resolve e filtros (clausula/veículo/contrato/valor) na aba Concluídos — reduz custo operacional (margem do cliente final).
- [ ] **[UX] Smart Defaulting:** Sistema de preenchimento inteligente de formulários baseado nos últimos registros inseridos (Redução de 60% no tempo de cadastro).

### [ ] Phase 10.11 — Automated Enterprise Showcase (Seed & Provisioning)

- [ ] **SuperAdmin Provisioning Script:** Desenvolvimento de script robusto de provisionamento automatizado (`make seed-enterprise`) para instanciar um Tenant isolado contendo volume real de veículos, contratos, zonas e telemetria pré-calculada para fins de demonstração de portfólio.

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
