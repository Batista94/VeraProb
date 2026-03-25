# VeraProb — Roadmap Estratégico Ativo

**Revisão:** 2026-03-24
**Status Atual:** Phase 9 em andamento (9.5–9.8 pendentes) · Phase 10.1 CONCLUÍDA — Milestone alvo: **READY FOR FIRST TENANT**
**Arquivo Histórico:** [roadmap_archive.md](roadmap_archive.md)

---

## Estado do Codebase

| Aspecto | Estado |
|---|---|
| Testes | 700 passing · 64 skipped · 0 falhas ✅ |
| Migrations | 73 aplicadas (schema lock v1) ✅ |
| Análise estática | 0 erros · 0 warnings · `flutter analyze` ✅ |
| Phase 10.1 | **CONCLUÍDA** — Schema Lock ✅ |

---

## Phase 9 — VeraProb: De Protótipo de Engenharia a Produto B2B Operacional

> [!CAUTION]
> **CRITICAL SECURITY BLOCKER (PHASE 9.8)**: O sistema contém a `service_role` key no bundle Flutter. **NÃO DEPLOYAR EM PRODUÇÃO** até migração para Edge Proxy.

### [ ] Phase 9.5 — Vínculo Dinâmico & UX do Operador (PRÓXIMA)
- **SLA Template Library:** Galeria de modelos pré-configurados (Fretamento, Carga Seca, etc.).
- **Smart Defaults (SQL-based):** Preenchimento preditivo baseado em Heurísticas históricos.
- **ServiceManifest:** Desacoplamento lógico entre ativos e obrigações contratuais.

### [ ] Phase 9.6 — Lógicas Matemáticas & Cockpit UI
- **Kinematic Guard (INV-25):** Validação matemática de telemetria ($v = \Delta d / \Delta t$) no banco.
- **Industrial Deep Theme:** Interface de alta performance (Slate/Zinc) para operações 24/7.
- **Heurísticas de Alerta:** Cálculo de impacto financeiro em tempo real.

### [ ] Phase 9.7 — Liveness & Resiliência Operacional
- **Background Sync Resilience:** Buffer local (SQLite) no Mobile para zonas de sombra.
- **Driver Defense Portal:** Justificativas preventivas vinculadas diretamente à auditoria.
- **Heartbeat Monitor:** Diferenciação técnica entre sabotagem e falhas de rede.
- **Late-Arrival Window Protocol:** Window de 48h para reprocessamento (INV-12).

### [ ] Phase 9.8 — Audit, Security & Identity
- **[CRITICAL] Edge Proxy:** Migração para Edge Functions (Remoção `service_role`).
- **WASM Build Hygiene:** Validação rigorosa de `flutter build web --wasm`.
- **Hard Quota Enforcement:** Triggers de limite para `max_vehicles` e `max_contracts`.
- **JWT Circuit Breaker:** Invalidação imediata de sessões para organizações suspensas.
- **Privileged Access Hardening:** MFA obrigatório para SuperAdmin.
- **Entity Alias Mapping (UI):** Tradução de UUIDs para nomes amigáveis em toda a jornada.
- **Justified Impersonation:** Logs de suporte com exigência de Ticket ID.

---

## Milestone Gate: READY FOR FIRST TENANT

**Status:** EM ANDAMENTO — 7/19 itens de Readiness concluídos.
Verificar checklists detalhados de readiness e testes manuais em [roadmap_archive.md](roadmap_archive.md#milestone-gate-ready-for-first-tenant).

---

## Phase 10 — CI/CD & Launch Preparation

### [ ] Phase 10.2 — WASM Build Validation
- Build web sem `dart:html`/`dart:js` · Freezed up-to-date.

### [ ] Phase 10.3 — Shadow Mode
- EvaluationEngine paralelo validado contra fluxos manuais.

### [ ] Phase 10.4 — OCC UX Polish
- Cognitive load audit · Verdict rastreável em ≤1 clique · WCAG 2.2 AA.

### [ ] Phase 10.5 — First Pilot Tenant Onboarding
- Provisionar tenant real · End-to-end validation · PO sign-off.

---

## Phase 11+ — VeraProb Enterprise: Escala & Integrações
API/Webhooks (SAP/Oracle), Captura Passiva (OCR/SDK), Assinatura JIT.
