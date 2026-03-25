# Milestones & Roadmap

## Current State

**Phase 9 (Technical Review & CI/CD Gate) — COMPLETE. All sub-phases [GO].**
**Gate `READY FOR CI/CD` — ACHIEVED.** Stable schema · RLS validated · test coverage >60% · Lead Reviewer [GO].
**Current Objective: Phase 10 — CI/CD & Launch Preparation.**
Gate target: `READY FOR FIRST TENANT` — WASM build passing · Shadow Mode validated · First pilot tenant onboarded.

### Phase 9 Sub-Phases (COMPLETE)

| Sub-Phase | Description | Status |
|---|---|---|
| 9.1 | SuperAdmin Audit Log | [GO] |
| 9.2 | SuperAdmin Management + Skills Sealing (INV-11) | [GO] |
| 9.3 | Auditor Reativo + INV-23 VerdictEvidence | [GO] |
| 9.4 | CI/CD Gate Validation | [GO] |

#### Phase 9.4 — CI/CD Gate Validation — **COMPLETE**

| Sub-fase | Descrição | Status |
|---|---|---|
| 9.4.1 | Correção Cirúrgica de Segurança | [GO] |
| 9.4.2 | Testes RLS de Isolamento Real (12 casos) | [GO] |
| 9.4.3 | Testes E2E JWT Hook (4 cenários) | [GO] |
| 9.4.4 | Cobertura ≥60% Aplicada em CI | [GO] |
| 9.4.5 | Triagem Cirúrgica de `dynamic` no Domínio | [GO] |
| 9.4.6 | Lead Reviewer Forensic Audit [GO] | [GO] |

---

### Phase 10 Sub-Phases (current)

| Sub-Phase | Description | Status |
|---|---|---|
| 10.1 | Schema Lock & Migration Freeze | [GO] |
| 10.2 | WASM Build Validation | [ ] |
| 10.3 | Shadow Mode | [ ] |
| 10.4 | OCC UX Polish | [ ] |
| 10.5 | First Pilot Tenant Onboarding | [ ] |

#### Phase 10 — CI/CD & Launch Preparation (current)

**Objetivo:** Declarar `READY FOR FIRST TENANT` satisfazendo os critérios do gate.

| Sub-fase | Descrição | Critérios de Conclusão |
|---|---|---|
| 10.1 | Schema Lock & Migration Freeze | Audit de todas as migrations · confirmar append-only · documentar schema final · branch `main` locked via CI |
| 10.2 | WASM Build Validation | `flutter build web --wasm` passing cleanly · zero `dart:html`/`dart:js` · all generated files up-to-date · build artifacts verified |
| 10.3 | Shadow Mode | EvaluationEngine rodando em modo paralelo contra dados reais sem emitir penalidades · output comparado com manual · divergências investigadas |
| 10.4 | OCC UX Polish | Cognitive load audit em todas as telas OCC · verdict traceability ≤1 click · WCAG 2.2 AA · "silence a contestation in 10s" standard met |
| 10.5 | First Pilot Tenant Onboarding | Provisionar primeiro tenant real · validar fluxo end-to-end (ingestion → ledger → OCC) · sign-off do PO |

---

## Milestone Gates

| Gate | Criteria | Signal |
|---|---|---|
| **Homologation Ready** | Phase 5 & 6 invariants passing · Core flows tested | `READY FOR HOMOLOGATION` |
| **Ingestion Validated** | Event Timeline Reconstruction passing Chaos Tests | `INGESTION ENGINE READY` |
| **CI/CD Ready** | Stable schema · RLS validated · Test coverage >60% | `READY FOR CI/CD` ✅ |
| **Product Launch Ready** | Isolation audited · Shadow Mode functional · First tenant onboarded | `READY FOR FIRST TENANT` |

## Phase Definitions

| Phase | Name | Key Deliverables |
|---|---|---|
| 5 | Contractual Engine | SLA rules, contractual plans, operational zones, INV-18 |
| 6 | Financial Ledger & Verdicts | Immutable ledger, `Money` VO, snapshots, INV-23 |
| 7 | Multi-Tenant Isolation | RLS hardening, INV-20 dual-key, tenant health panel |
| 8 | Telemetry Integrity | Anti-spoofing (INV-21), auditor queue, risk scoring |
| 8.8 | Telemetry Integrity Polish | `SpoofingDetector` + `SpoofingRiskScore` + `VerdictEvidence` — **COMPLETE** |
| 9 | Technical Review & Polish | Invariant audit, test coverage >60%, Lead Reviewer [GO]s — **COMPLETE** |
| 9.4 | CI/CD Gate Validation | RLS tests reais · JWT hook E2E · cobertura ≥60% em CI · triagem dynamic · [GO] — **COMPLETE** |
| 10 | CI/CD & Launch Preparation *(current)* | Schema lock · WASM build · Shadow Mode · OCC UX polish · First pilot tenant |

## Invariant Implementation Status

| Invariant | Phase | Status |
|---|---|---|
| INV-1 — Immutable Ledger | 6 | Active |
| INV-2 — Financial Precision | 6 | Active |
| INV-6 — Multi-Tenant RLS | 7 | Active |
| INV-10 — RLS Tenant Claim | 7 | Active |
| INV-18 — Engine Activation Gate | 5 | Active |
| INV-20 — Dual-Key Isolation | 7 | Active |
| INV-21 — Anti-Spoofing Detector | 8 | Active |
| INV-23 — Verdict Explainability | 9.3 | Active |
| INV-24 — Idempotent Ingestion | 8 | Active |
