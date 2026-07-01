# VeraProb — Active Strategic Roadmap

**Revision:** 2026-07-01
**Current Status:** Phase 10.7 backend-first entregue (Sealed Verdict Webhook engine — Transactional Outbox + dual-path dispatch, HMAC per-org, SSRF-hardened; test-db 1459 PASS, deno 6/0, scanner [GO], lead-reviewer [GO], UAT-1 webhook.site verde) · [NEXT: UI Tenant Admin de webhooks (10.7 separado) + trilha de notificação Resend na resolução]

---

## Codebase Status

| Aspect | Status |
| :--- | :--- |
| DB Tests (pgTAP) | 1459+ passing · 130 files · `make test-db` ✅ |
| Migrations | 331 committed ✅ |
| Static Analysis | 0 errors · 0 warnings · `flutter analyze` ✅ |
| CI Regression | Zero-Trust Data Masking & Retract State Leak → resolvido por `20260901000004` ✅ |

> **Regressão crítica fechada (2026-06-24):** Correção de vazamento de estado (`disputed_by` não era limpo em retração) via `20260901000001`; Enforcement de `NOWAIT` concurrency lock nas filas do portal via `20260901000002`; Hardening do Zero-Trust (`read_infraction_context` ocultando dados para inquilinos em disputas abertas) via `20260901000003` e `000004`. Testes forenses refatorados para manter compliance com a Enterprise Directive e INV-23. pgTAP 100% verde (1343 tests).

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 4 itens de Readiness pendentes.

### Checklist "READY FOR FIRST TENANT" (Pending)

- [ ] **Custom RBAC (Dynamic Tenant Roles):** A arquitetura deve permitir que o **Tenant Admin** (Administrador da Organização cliente) crie "Perfis de Acesso" customizados via UI e defina quais telas/KPIs cada perfil pode ver (ex: isolar a visão do Dashboard Financeiro de operadores logísticos comuns). O SuperAdmin do VeraProb apenas gerencia os Tenants e os Tenant Admins, não os perfis internos do cliente.
- [ ] **Financial Guard (Penalty Stop-Loss Cap):** Obrigatório para evitar que falhas de telemetria gerem faturamento infinito (limite de teto de multa por evento/contrato).
- [ ] **Legal Gate & Terms of Use (LGPD):** Bloqueio de acesso ao sistema/telemetria pendente de aceite explícito do contrato de custódia de dados.
- [x] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing. *(Entregue Fase 10.7 — engine backend-first; UAT-1 webhook.site verde.)*
- [ ] **SLA Sandbox:** Functional 'Sandbox' system for basic SLA model simulation.

---

## Phase 10 — CI/CD & Launch Preparation

- [x] **[CI/CD] Enterprise GitHub Actions Pipelines:** Automação de pipelines de CI/CD com barreiras automáticas de migração (Append-Only Gate), varredura estática de segurança (`pr_full_scanner.sh`), testes pgTAP, testes de unidade/widgets Flutter e testes E2E para staging/production.

### [x] Phase 10.4.C — Forensic Evidence Snapshot & Immutability (Concluído)

### [x] Phase 10.5 — Core Transactional Integrity (Prioridade Máxima) (Concluído)

### [x] Phase 10.6 — Forensic Operations & Dispute Reality (Concluído)

> **Plano v3 (council-remediated) entregue 2026-06-12** — Componentes 1-5. Migrações `20260813000001`…`20260814000004` (15) + edge fns `verify-evidence-hash`, `notify-sla-breach`. `make test-db` 824 PASS. CI E2E pendente de re-run após fix do grant MFA (`20260815000000`).

- [x] **[Comp 1] Anexo de evidência do contratante:** Canal de upload (foto/doc/telemetria externa) vinculado por `organization_id` (INV-1) e selado por SHA-256 (INV-9). Bucket de storage com gate por org + RPC `attach_dispute_evidence` + RPC `verify_evidence_hash`. O auditor decide *sobre* algo.
- [x] **[Comp 2] Taxonomia de motivos (reason codes) vs texto livre:** Enum versionado de motivos agnóstico (B6: `SENSOR_FAULT`, `CONTRACT_EXCEPTION`, `OTHER`, `LEGACY_UNCLASSIFIED`…) + campo livre opcional. Colunas `rejection_reason_code`/`resolution_reason_code`. Feed de curadoria (`v_reason_code_curation_candidates`) para promover texto recorrente a códigos globais.
- [x] **[Comp 3] Trilha de "quem cancelou":** No retract, `disputed_at`/`disputed_by` selados no open (INV-15) e NUNCA limpos (INV-23) — provenance sobrevive ao retract. Exposto na timeline do card + `RetractionProvenance` widget.
- [x] **[Comp 3] SLA-timer de disputa (aging):** Prazo de resolução em dias úteis (`resolution_due_at`) com calendário de feriados por org (`organization_holidays`). `DisputeSlaChip` (countdown/overdue) no card. RPC `dispute_open` semeia o prazo.
- [x] **[Comp 5.3] Forensic Dispute Portal (ReadOnly):** Tela externa tokenizada (link temporário TTL) para transportadores verem evidências sem login no core. Tokens (`dispute_portal_tokens`) + RPC `read_dispute_portal` + tipos de ledger de portal. (Stub ReadOnly; submissão de contraprova = backlog 10.7.)
- [x] **[BIZ] Forensic Dispute Portal (submissão):** Interface externa para carriers submeterem contraprovas digitais. Entregue com retry logic, validação de input, e UI state management.
- [x] **WS-9: Signal Integrity Monitor:** Lógica SQL/Dart para detectar 'GPS Jumps' e inconsistências na telemetria, gerando um 'Confidence Score' no card. (Pausado da Fase 10.4)
- [x] **[BIZ] Real-time Risk Thermometer:** Visualização preditiva de quebra de SLA (ETA vs Prazo do Contrato) para ação preventiva do operador. *(Sprint C — `get_fleet_risk_summary` RPC; risk_bps server-side byte-idêntico ao `SlaBreachRiskCalculator`, INV-15; substitui o loop Dart em `atRiskSlaCountProvider`.)*
- [x] **[BIZ] SLA Versioning & Lifecycle:** Version control system for SLA models with mandatory effective dates and retirement workflows. *(Sprint B — schedule/activate/retire RPCs, anti-backdating 2-camadas, amendments financeiros append-only, snapshot INV-21.)*
- [x] **[Comp 5.4 · BIZ] Human Verdict Affirmation:** Botões `AFIRMAR VIOLAÇÃO` (sela hash) / `INIBIR VIOLAÇÃO` (comentário obrigatório) + fluxo de confirmação (`CONFIRMAR AFIRMAÇÃO`/`CONFIRMAR INIBIÇÃO`/`CANCELAR SOLICITAÇÃO`) direto no `SanctionVerdictCard`. Cobertura de widget 43 testes.
- [x] **[BIZ] One-Click Evidence Package:** Instant forensic dossier generator (Map + Telemetry + Hash + Contract) in PDF for defense against undue fines.
- [x] **[BIZ] Evidence Package (One-Click Dossier):** Função de exportação consolidada contendo Telemetria + Provas Fotográficas + Snapshot do Contrato assinado.
- [x] **[BIZ] Carrier Performance Ranking:** Dashboard de 'Leaderboard' que classifica transportadores por índice de violações e conformidade contratual. *(Sprint C — `mv_carrier_performance` MV + pg_cron horário + `get_carrier_performance_ranking` RPC SECURITY DEFINER; `CarrierRankTable`.)*
- [x] **[BIZ] Ingestion Health Monitor:** Real-time data integrity dashboard to detect telemetry gaps and hardware failures. *(Entregue 2026-06-24 — `get_fleet_health_status` RPC SECURITY DEFINER, `IngestionHealthScreen`, `FleetHealthSummaryBar`, `VehicleHealthCard`, `fleet_health_providers`, `SupabaseFleetHealthQueryService`. `HardwareStatusView` INV-13 VO; `fleetActiveRatioBps` int bps convention. Migrations `20260902000001`+`20260902000002`. Branch `feature/sparklines`.)*
- [x] **[BIZ] Digital Audit Acknowledgement:** Carrier/driver fine acceptance workflow to accelerate billing cycles. *(Sprint A — `acknowledge_via_portal` hash-bound + `acknowledge_sanction_internal`; status terminal `acknowledged`; fato ledger `SANCTION_ACKNOWLEDGED`.)*
- [x] **[UX] Financial Sparklines:** Mini-trend charts (sparklines) in Financial Impact cards for daily volatility visualization. (Movido da Fase 10.4)
- [x] **[UX] Data Integrity Drill-down:** Functional links from 'Incomplete Report' alerts to the telemetry Health Dashboard. (Movido da Fase 10.4)
- [x] **[BIZ] Sanction Auto-Resolution Trigger:** Expansão dos gatilhos de sanção para auto-resolver todos os tipos de alerta relacionados (por case key) de forma automática.

### [/] Phase 10.7 — Enterprise Integration & Event Dispatch

> **Plano de Arquitetura — Webhook de Veredito Selado (council, 2026-06-30, v2 endurecida) — ENTREGUE 2026-07-01** — Transactional Outbox + dual-path (kick imediato pós-RPC + GHA cron reconciliador). Assinatura HMAC-SHA256 por org com congelamento de versão de chave. SSRF anti-DNS-rebinding (resolve→valida→pin IP). At-least-once + idempotência no receptor. Migrações `20260904000001`…`20260905000003` (7) + edge fn `dispatch-verdict-webhooks` + kicker Dart + GHA `webhook-dispatch.yml`. Gates: test-db 1459 PASS, deno 6/0, scanner [GO], lead-reviewer [GO], UAT-1 webhook.site verde. Commits `19cc79fa`…`03c78c1a` na branch `feature/enterprise-integrations`. Pendente: UI Tenant Admin (10.7 separado) + Gate 8 PR→main + UAT-2 (secrets CI).

- [/] **[BIZ] Webhook de Veredito Selado — dispatch engine (backend-first entregue · UI pendente):**
  - [x] Tabela `webhook_signing_keys` (chave de saída por org, versionada, status active/retiring/revoked, janela de graça 24h).
  - [x] Tabela `webhook_endpoints` (config por org, `last_kick_at` rate-limit, guarda SSRF, soft-delete, RLS Tenant Admin).
  - [x] Tabela `webhook_delivery_logs` (outbox append-only imutável: `PENDING|DELIVERING|SUCCESS|FAILED|DEAD`, `signing_key_id` e `ledger_entry_id` próprios, retry/backoff, enqueue idempotente).
  - [x] Trigger `enqueue_verdict_webhooks` AFTER INSERT em `sla_audit_ledger_v2` (tipos terminais) — outbox, zero HTTP em txn.
  - [x] Edge fn `dispatch-verdict-webhooks` (dois modos de auth, SSRF Deno.startTls, SKIP LOCKED, cross-verify de hash V4, backoff, dead-letter).
  - [x] Kick imediato Dart pós-commit (fire-and-forget) na camada application/infrastructure (`webhook_dispatcher_port` + `supabase_webhook_dispatch_kicker`).
  - [x] GHA cron reconciliador `webhook-dispatch.yml` (retry de FAILED, `*/5`).
  - [x] Testes pgTAP (7) + Deno (6/0) + Dart cobrindo V1–V5 + planos 1:1; Council + Skills [GO].
  - [ ] (10.7 separado) UI Tenant Admin: CRUD endpoints, Delivery Log viewer, replay manual, secret reveal-once.

- [x] **Webhook Endpoint:** Functional 'Sealed Verdict' webhook for external integration testing.
- [x] **[BIZ] Webhooks & API-First Integration:** Anticipated from Phase 11. Implement 'Sealed Verdict' Webhooks (JSON) for immediate SAP/Oracle/ERP integration. *(Entregue Fase 10.7 — payload JSON assinado HMAC per-org; consumível por SAP/Oracle/ERP.)*
- [/] **Notificação/webhook na resolução:** Edge fn `notify-sla-breach` (Comp 5.1) entregue para disparo de breach. Falta o gancho de notificação ao contratante *na resolução* da disputa (Resend/PostHog) — transparência + reduz re-contestação.
- [ ] **[BIZ] Data Extract & Reporting API:** Criação de endpoints de exportação de dados agregados (CSV/JSON) e chaves de API Read-Only para que o C-Level do cliente possa conectar seus painéis do PowerBI diretamente às Views de ROI (`v_roi_summary`) e `contractual_financial_snapshot`.

### [ ] Phase 10.8 — Shadow Processing & ROI Proving

- [ ] **SLA Sandbox (ROI Simulator):** Lógica em SQL/Edge Functions para simular 'E se...' (What-if analysis) rodando novos modelos de SLA contra dados históricos para provar economia financeira.
- [ ] **[BIZ] SLA Sensitivity Analysis:** Financial prediction tool based on historical data to simulate the impact of new SLA rules on past performance. *(MOVIDO → Fase 10.8 — fundir com SLA Sandbox; design `simulate_rule_sensitivity` arquivado como fundação.)*

### [ ] Phase 10.9 — Governance, Legal & Anti-Fraud

- [x] **Self-Service Onboarding:** Fluxo assistido de onboarding de Tenants com validações rigorosas (Wizard UI com CNPJ autofill) e MFA enrollment para o Super Admin.
- [x] **[BIZ] Immutable Admin Log (Meta-Audit):** Tabela de auditoria de sistema (Meta-Audit) implementada para registrar e inspecionar quem alterou regras de SLA e configurações críticas (Visualização de Diff de Payload via painel Super Admin).
- [x] **[BIZ] Configuration Audit Log:** Immutable meta-audit of changes to SLA models, contracts, and permissions (Who changed the rule and when?). Concluído junto com o Meta-Audit.
- [ ] **[BIZ] Systemic Fraud Detection:** Automatic behavioral alerts for operator deviations (e.g., excessive inhibitions for specific carriers).
- [/] **[BIZ] Data Lifecycle Management (LGPD):** Automatic retention engine (5 years for evidence, 1 year for raw telemetry) for legal compliance.
- [x] **[BIZ] Tenant Lifecycle Management:** Funções de 'Reenviar Convite', 'Editar Dados' e 'Arquivar Tenant' (Soft Delete para preservar a Cadeia de Custódia de dados passados).
- [x] **Support Impersonation Security:** "Grant Support Access" button with mandatory audit log and auto-expiry (Impersonation banner implementado).
- [ ] **[BIZ] Progressive Penalty Engine (INV-28):** Support for time-scaled fines that increase based on infringement duration.
- [ ] **[BIZ] Multi-Level Org Hierarchy:** Sub-tenant structure for large corporations (HQ > Branch > Cost Center) with rule inheritance and data isolation.
- [ ] **[BIZ] Partner Billing Reconciliation:** Invoice crossing tool (CSV Upload) against the immutable Ledger for identifying billing discrepancies.
- [ ] **Automated Billing Provisioning (Stripe/Stax):** Integration/placeholder for billing account provisioning at Org creation.
- [ ] **Tenant Heartbeat Dashboard:** SuperAdmin view of "Signal Health" (GPS success rate vs hardware failures).

### [ ] Phase 10.10 — Bulk Operations & Convenience (Conveniência e Ações em Massa)

- [ ] **[UX] Auditor Productivity Dashboard:** Transform the 'Auditee Queue' into a performance center with metrics for response time, verdict accuracy, and daily throughput. *(DIFERIDO pós-first-tenant — precisa de volume real de fila; 10.10 bulk-resolve é a maior alavanca para a mesma persona.)*
- [ ] **[BIZ] Rule Update Consent Flow (Contractor Sign-off):** Implementar fluxo de consentimento/aceite digital por parte da transportadora quando regras ou penalidades de SLA forem alteradas ou renegociadas no Rule Studio, mitigando riscos de alegações de alteração unilateral de regras em auditorias futuras.
- [ ] **[UX] Bulk Action Mode:** Seleção múltipla de infrações na Fila Auditora para tratamento em massa (Batch Processing).
- [ ] **WS-7: Operational Macros (1-Click Verdict):** Atalhos para vereditos comuns (ex: 'Blitz', 'Trânsito') que preenchem justificativa e aplicam regras de tolerância automaticamente.
- [ ] **Resolução em lote + filtros:** Auditor com fila grande precisa de bulk-resolve e filtros (clausula/veículo/contrato/valor) na aba Concluídos — reduz custo operacional (margem do cliente final).

---

## UI/UX General Polish

- [ ] **Empty State UX:** Substituir placeholders 'Nenhum registro' por guias contextuais (Empty State Onboarding).
- [ ] **Skeletal Loading:** Implementar Shimmer Effect em 100% das listas para melhorar a percepção de performance.

---

## Technical Debt & Maintenance

- **[TECH] Batch RPC Schema Sync:** `batch_update_vehicles` e `batch_update_contracts` (migration `20260412000004`) são funções hardcoded. Ao adicionar colunas atualizáveis a `vehicles` ou `contracts`, adicionar a linha `COALESCE` correspondente nas funções. Backlog: substituir por script de geração estática em CI/CD (evita risco de PL/pgSQL dinâmico e conflitos de placeholders `format()` vs `RAISE`).
- [x] **[TEST] SLA Template Editor Dialog Refactoring:** Modularização e substituição da suite monolítica de testes (~2.6k LOC) por 12 suites baseadas em Robot Pattern, blindando regras de integridade e CIA triad.

---

## Phase 11+ — VeraProb Enterprise: Scale & Integrations

API/Webhooks (SAP/Oracle), Passive Capture (OCR/SDK), JIT Signature.

- [ ] **[BIZ] Bulk SLA Rule Importer (CSV):** Implementar funcionalidade de importação em massa para parâmetros de regras de SLA vinculadas a contratos (multas, limites de tolerância), evitando a necessidade de cadastro manual individual pós-importação de contratos.
- [ ] **[BIZ] Bulk Contract Importer (CSV):** Implementar motor de carga em massa para contratos com etapa de Pre-flight Validation (exibe erros de formatação antes de gravar no banco).
- [ ] **WS-8: Keyboard-First Navigation:** Implementar atalhos de teclado para navegação ultra-rápida na Fila Auditora (Focus Management entre cards).
- [ ] **[UX] Smart Defaulting:** Sistema de preenchimento inteligente de formulários baseado nos últimos registros inseridos (Redução de 60% no tempo de cadastro).
- [ ] **SuperAdmin Provisioning Script:** Desenvolvimento de script robusto de provisionamento automatizado (`make seed-enterprise`) para instanciar um Tenant isolado contendo volume real de veículos, contratos, zonas e telemetria pré-calculada para fins de demonstração de portfólio.
