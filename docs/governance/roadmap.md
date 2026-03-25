# VeraProb — Roadmap Estratégico

**Revisão:** 2026-03-24
**Status Atual:** Phase 10 em andamento — Milestone alvo: **READY FOR FIRST TENANT**

---

## Estado do Codebase (referência para novas sessões)

| Aspecto | Estado |
|---|---|
| Testes | 700 passing · 64 skipped (Supabase offline) · 0 falhas ✅ |
| Migrations | 73 aplicadas (schema lock v1 — append-only) |
| Command Handlers | 17 handlers na camada `application/` |
| Análise estática | 0 erros · 0 warnings · `flutter analyze --no-pub` ✅ |
| CI/CD | `flutter analyze` + `flutter test` passando no GitHub Actions ✅ |
| Precisão financeira | `Money` VO (centavos BIGINT) — Enforced ✅ |
| Phase 10.1 | **CONCLUÍDA** — Schema Lock + Migration Freeze + CI append-only guard ✅ |
| Phase 9.4 Audit | **CONCLUÍDA** — Dashboard ROI + CNPJ Auto-fill ✅ |
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

## Phase 9 — VeraProb: De Protótipo de Engenharia a Produto B2B Operacional

> [!CAUTION]
> **CRITICAL SECURITY BLOCKER (PHASE 9.8 — ITEM 12)**: O sistema contém a `service_role` key no bundle Flutter. **NÃO DEPLOYAR EM PRODUÇÃO** até migração para Edge Proxy.

**Mandato de Testes:** Unit, Integration, E2E e Manual (Human-in-the-Loop).

---

### [x] Phase 9.4 — ROI Dashboard & Precision Onboarding ✅ CONCLUÍDA
**Líder:** Senior Engineer + Lead Reviewer · **Verdict:** [GO] · **Data:** 2026-03-24

**Destaques entregues:**
- **Dashboard Executivo (KPI Modular):** FPS banner, 5 KPI cards (Receita Blindada, Taxa Recuperação, Dispute-to-Resolution, Conformidade SLA, **Economia BRL**), distribuição de receita, Shadow Mode ROI card.
- **CNPJ Auto-fill (ReceitaWS):** Lookup paralelo ao check de unicidade; preenche Razão Social e Nome Fantasia automaticamente; chip de confirmação + alerta de empresa inativa.
- **Shadow Mode ROI:** Motor "What-if" completo com persistência e dashboard integrado.
- **Fix INV-4:** `_ShadowModeCard` corrigido de `dynamic` para `ShadowModeSimulation` tipado.

**Nota:** Usage Metering Ledger (lastro de billing variável) movido para **Phase 10+** — não é gate para READY FOR FIRST TENANT.

### [ ] Phase 9.5 — Vínculo Dinâmico & UX do Operador
**Destaques:** 
- **SLA Template Library:** Galeria de modelos pré-configurados (Fretamento, Carga Seca, etc.) para acelerar o setup operacional.
- **Smart Defaults (SQL-based):** Preenchimento preditivo baseado em Heurísticas de Frequência histórica de Placa/Motorista.
- **ServiceManifest:** Desacoplamento lógico entre ativos e obrigações contratuais para flexibilidade JIT.

### [ ] Phase 9.6 — Lógicas Matemáticas & Cockpit UI
**Destaques:** 
- **Kinematic Guard (INV-25):** Validação matemática de telemetria ($v = \Delta d / \Delta t$) para invalidação de fraude no nível do banco.
- **Industrial Deep Theme:** Interface de alta performance e baixa fadiga visual (Slate/Zinc) para operações 24/7.
- **Heurísticas de Alerta:** Cálculo de impacto financeiro em tempo real para priorização de incidentes.

### [ ] Phase 9.7 — Liveness & Resiliência Operacional
**Destaques:** 
- **Background Sync Resilience:** Buffer local (SQLite) no Mobile para garantir a cadeia de custódia em zonas de sombra (sem 4G).
- **Driver Defense Portal:** Interface para justificativas preventivas (fotos/evidências) vinculadas diretamente à auditoria.
- **Heartbeat Monitor:** Diferenciação técnica entre sabotagem de hardware e falhas de infraestrutura de rede.
- **Late-Arrival Window Protocol:** Definição de janela temporal (ex: 48h) para reprocessamento determinístico de eventos atrasados sem violação da INV-12.

### [ ] Phase 9.8 — Audit, Security & Identity
**Destaques:** 
- **[CRITICAL] Edge Proxy:** Migração total para Edge Functions e remoção definitiva da `service_role` do frontend.
- **WASM Build Hygiene:** Validação rigorosa de `flutter build web --wasm` com remoção total de dependências `dart:html/js`.
- **Schema Lock Protocol:** Auditoria de migrations para garantir imutabilidade e travamento de novos schemas pós-lançamento.
- **Hard Quota Enforcement (DB Level):** Implementação de triggers BEFORE INSERT para garantir que limites de `max_vehicles` e `max_contracts` sejam respeitados no banco.
- **JWT Circuit Breaker:** Mecanismo de invalidação imediata de sessões para organizações suspensas ou inadimplentes.
- **Privileged Access Hardening:** Implementação de MFA obrigatório e TTL reduzido para sessões de SuperAdmin.
- **Entity Alias Mapping (UI):** Camada de tradução de UUIDs para nomes amigáveis (Placas, Clientes) em toda a jornada.
- **Iterative Auditing:** Introdução do estado `PENDING_MORE_INFO` no workflow de sanções forenses.
- **Justified Impersonation:** Logs de suporte com exigência de Ticket ID e motivo, auditáveis pelo cliente final.

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
| ✅ Dashboard ROI com KPIs modulares & "Economia BRL" | 9.4 | OK |
| ✅ Automação de Onboarding (CNPJ Auto-fill via ReceitaWS) | 9.4 | OK |
| [ ] Biblioteca de SLA Templates operacional | 9.5 | |
| [ ] Smart Defaults reduzindo tempo de despacho | 9.5 | |
| [ ] Kinematic Guard bloqueando Fake GPS no banco | 9.6 | |
| [ ] Interface Cockpit em Industrial Deep Theme | 9.6 | |
| [ ] Sincronismo Offline (Cadeia de Custódia) | 9.7 | |
| [ ] Late-Arrival Window Enforcement (INV-12) | 9.7 | |
| [ ] Heartbeat Monitor diferenciando sabotagem | 9.7 | |
| [ ] Hard Quotas (DB-enforced) para Billing | 9.8 | |
| [ ] JWT Circuit Breaker (Kill Switch) | 9.8 | |
| [ ] MFA mandatório para SuperAdmin | 9.8 | |
| [ ] Edge Proxy (Removido service_role key) | 9.8 | |
| [ ] Build WASM limpo (zero dart:html/js) | 9.8 | |
| [ ] Schema Lock e Migration Audit | 9.8 | |
| [ ] Entity Alias Mapping em todo o sistema | 9.8 | |
| [ ] Justified Impersonation com Log de Suporte | 9.8 | |

---

## Phase 10 — CI/CD & Launch Preparation

**Gate target:** `READY FOR FIRST TENANT`

### [x] Phase 10.1 — Schema Lock & Migration Freeze ✅ CONCLUÍDA
**Data:** 2026-03-24
- 73 migrations auditadas · CI append-only guard (pr_scanner.sh) · schema_lock_v1.md
- Security hardening migration `20260413000001` incluída
- `flutter analyze --no-pub` → 0 issues (700 passing · 0 failures)

### [ ] Phase 10.2 — WASM Build Validation
- `flutter build web --wasm` deve passar sem `dart:html`/`dart:js`
- Todos os arquivos Freezed up-to-date
- Zero incompatibilidades Wasm no bundle

### [ ] Phase 10.3 — Shadow Mode
- EvaluationEngine paralelo sem emitir penalidades
- Output comparado com fluxo manual

### [ ] Phase 10.4 — OCC UX Polish
- Cognitive load audit · verdict rastreável em ≤1 clique · WCAG 2.2 AA

### [ ] Phase 10.5 — First Pilot Tenant Onboarding
- Provisionar tenant real · validação end-to-end · PO sign-off

---

## Phase 11+ — VeraProb Enterprise: Escala & Integrações
**Destaques:** API/Webhooks (SAP/Oracle), Captura Passiva (OCR/SDK), Assinatura JIT, Expansão Vertical Agnostica.

---

## Visão Geral de Execução

```
═══════════════════════════════════════════════════════════════════════
[x] Phase 9.1, 9.2, 9.3, 9.4 COMPLETE ✅
[x] Phase 10.1 — Schema Lock & Migration Freeze ✅
═══════════════════════════════════════════════════════════════════════
[ ] Phase 10.2 — WASM Build Validation          ← PRÓXIMA
[ ] Phase 10.3 — Shadow Mode
[ ] Phase 10.4 — OCC UX Polish
[ ] Phase 10.5 — First Pilot Tenant Onboarding
───────────────────────────────────────────────────────────────────────
>>> MILESTONE: READY FOR FIRST TENANT <<<
───────────────────────────────────────────────────────────────────────
[ ] Phase 11+ — Enterprise Expansion
═══════════════════════════════════════════════════════════════════════
```
