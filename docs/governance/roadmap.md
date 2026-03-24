# PactaFlow — Roadmap Estratégico

**Revisão:** 2026-03-24
**Status Atual:** Phase 9 em andamento — Milestone alvo: **READY FOR FIRST TENANT**

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---|---|
| Testes | 654 passing · 0 falhas ✅ |
| Migrations | 48 aplicadas |
| Command Handlers | 17 handlers na camada `application/` |
| Análise estática | 0 erros · Wasm-ready (`package:web`) |
| Precisão financeira | `Money` VO (centavos BIGINT) — Enforced ✅ |
| Phase 9.3 Audit | **CONCLUÍDA** — Testes manuais aprovados ✅ |
| Phase 9.2 Audit | **CONCLUÍDA** ✅ |
| Phase 9.1 Audit | **CONCLUÍDA** ✅ |

---

## Milestone Gates

| Gate | Critério | Sinal |
|---|---|---|
| Homologation Ready | Invariantes 5 & 6 passando · Flows core testados | ✅ ATINGIDO |
| Ingestion Validated | Timeline Reconstruction passando Chaos Tests | ✅ ATINGIDO |
| CI/CD Ready | Schema estável · RLS validado · Cobertura >60% | ✅ ATINGIDO |
| **Product Launch Ready** | SuperAdmin operacional · Auditor reativo · Verdict explicável · ROI dashboard | **READY FOR FIRST TENANT** |

---

## Fases Concluídas (Detalhes)

### Phase 9.1 — Forensic Audit Geral ✅ CONCLUÍDA
**Líder:** Lead Reviewer · **Score:** 10/10 · **Verdict:** [GO] · **Data:** 2026-03-19
Validado: Dual-Key RLS · JWT path canônico · Event Time no Engine (INV-12) · Hash Chain em `TelemetryEvidence` (INV-24) · `Money` VO BIGINT (INV-2) · Wasm-readiness.

---

### Phase 9.2 — SuperAdmin Portal ✅ CONCLUÍDA
**Líder:** Lead Reviewer · **Score:** 10/10 · **Verdict:** [GO] · **Data:** 2026-03-19
**Gap Endereçado:** Criar cliente manualmente no banco não escala. 10 clientes = 10 intervenções de DBA.

**Deliverables:**
1. Rota `/super-admin` isolada.
2. Wizard "Gerar Nova Organização".
3. Painel de Tenant Health.
4. Tabela `tenant_billing_events` (INV-1).
5. `system_audit_log` exposto.

---

### Phase 9.3 — Auditor Reativo ✅ CONCLUÍDA
**Líder:** Senior Engineer + QA & Security Lead · **Verdict:** [GO] · **Data:** 2026-03-23
**Gap Endereçado:** Auditor passivo para reativo, combo de prova imutável (INV-23).

**Deliverables:**
1. `VerdictEvidence` VO (SHA-256).
2. Máquina de estados no ledger (RECOMMENDED -> APPLIED/REJECTED).
3. `sanction_review_queue` automática via triger.
4. `AuditorQueueScreen` com Supabase Realtime.
5. Badges de notificação em tempo real.
6. Testes Manuais (MT-9.3.1 a MT-9.3.10) aprovados.

---

## Histórico Antigo (Fases 5 a 8.8)

- **Phase 8.8 — Anti-Spoofing** ✅: GPS Falsificado e Hash Chain.
- **Phase 8.7 — Disaster Recovery** ✅: Runbook e PITR.
- **Phase 8.6 — Performance** ✅: 1k VUs k6.
- **Phase 8.5 — Security** ✅: Strict casts e PII masking.
- **Phase 8.4 — Observabilidade** ✅: Sentry + PostHog.
- **Phase 8.3 — Ambientes** ✅: Multi-env suporte.
- **Phase 8.2 — CI/CD** ✅: GitHub Actions.
- **Phase 8.1 — UX** ✅: Material 3.
- **Phase 7.5 — Financial Defense** ✅: PostgreSQL Blindagem.
- **Phase 7 — Exports** ✅: Relatórios imutáveis.
- **Phase 6 — Admin** ✅: RBAC e Convites.
- **Phase 5 — Foundation** ✅: RLS Isolation.

---

## Phase 9 — PactaFlow: De Protótipo de Engenharia a Produto B2B Operacional

> [!CAUTION]
> **CRITICAL SECURITY BLOCKER (PHASE 9.8 — ITEM 12)**: O sistema contém a `service_role` key no bundle Flutter. **NÃO DEPLOYAR EM PRODUÇÃO** até migração para Edge Proxy.

**Mandato de Testes:** Unit, Integration, E2E e Manual (Human-in-the-Loop).

---

### [ ] Phase 9.4 — ROI Dashboard + Shadow Mode (Demonstração de Valor)
**Destaques:** Painel de Valor Entregue (BRL), Shadow Mode (Demo de Vendas via CSV), Usage Metering Ledger, CNPJ Auto-fill.

### [ ] Phase 9.5 — Vínculo Dinâmico Contrato-Viagem
**Destaques:** Desacoplamento ativo-contrato via `ServiceManifest`, Smart Defaults no despacho.

### [ ] Phase 9.6 — Inteligência de Alertas
**Destaques:** Impacto financeiro estimado nos alertas, Alertas Preditivos (ETA breach), OCC reformulado.

### [ ] Phase 9.7 — Liveness Check, Late-Arrival & Anti-Tamper
**Destaques:** Silêncio como evento auditável (`SIGNAL_LOSS_BREACH`), Reprocessamento de eventos tardios.

### [ ] Phase 9.8 — Audit Trail do Sistema e Preparação ISO 27001
**Destaques:** [CRITICAL] Edge Proxy para SuperAdmin, Impersonation Audit, Self-Service Org Settings, Iterative Auditing.

---

### Milestone Gate: READY FOR FIRST TENANT

**Sinal:** **READY FOR FIRST TENANT** ✅

| Checklist | Sub-fase | Status |
|---|---|---|
| ✅ Novo tenant onboardado em <5 min, zero DBA | 9.2 | OK |
| ✅ Auditor notificado de breach em <30s | 9.3 | OK |
| ✅ Zero penalidade aplicada sem aprovação humana | 9.3 | OK |
| ✅ 100% das sanções com VerdictEvidence (INV-23) | 9.3 | OK |
| ✅ Testes Manuais MT-9.3.1 a MT-9.3.10 | 9.3 | **PASSED** ✅ |
| [ ] Dashboard ROI exibe "valor entregue em R$" | 9.4 | |
| [ ] Shadow Mode gera relatório "se você tivesse" | 9.4 | |
| [ ] Reatribuição dinâmica de ativo | 9.5 | |
| [ ] OCC identifica top-3 riscos em <10s | 9.6 | |
| [ ] Silêncio de rastreador gera SIGNAL_LOSS_BREACH | 9.7 | |
| [ ] Trilha de auditoria completa para qualquer entidade | 9.8 | |
| [ ] Edge Proxy para SuperAdmin (Security Gate) | 9.8 | |

---

## Phase 10 — PactaFlow Enterprise: Escala & Integrações
**Destaques:** API/Webhooks (SAP/Oracle), Captura Passiva (OCR/SDK), Assinatura JIT, Expansão Vertical Agnostica.

---

## Visão Geral de Execução

```
═══════════════════════════════════════════════════════════════════════
[x] Phase 9.1, 9.2, 9.3 COMPLETE ✅ (Manual Tests Passed)
═══════════════════════════════════════════════════════════════════════
[ ] Phase 9.4 — ROI Dashboard + Shadow
[ ] Phase 9.5 — Vínculo Dinâmico
[ ] Phase 9.6 — Inteligência de Alertas
[ ] Phase 9.7 — Liveness + Late-Arrival
[ ] Phase 9.8 — Audit Trail + ISO 27001
───────────────────────────────────────────────────────────────────────
>>> MILESTONE: READY FOR FIRST TENANT <<<
───────────────────────────────────────────────────────────────────────
[ ] Phase 10+ — Enterprise Expansion
═══════════════════════════════════════════════════════════════════════
```
