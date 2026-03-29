# VeraProb — Roadmap de Fases Concluídas (Arquivo)

Este documento contém o registro histórico de todas as fases já entregues do projeto VeraProb.
Utilize este arquivo apenas para consulta histórica. O estado atual deve ser guiado pelo `roadmap.md` ativo.

---

## Fases 1 a 8.8 (Foundation & Core Hardening)

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

### Phase 9.1 — Forensic Audit Geral ✅ CONCLUÍDA

- **Data:** 2026-03-19
- Validado: Dual-Key RLS · JWT path canônico · Event Time no Engine (INV-12) · Hash Chain em `TelemetryEvidence` (INV-24) · `Money` VO BIGINT (INV-2) · Wasm-readiness.

### Phase 9.2 — SuperAdmin Portal ✅ CONCLUÍDA

- **Gap:** Criar cliente manualmente no banco não escala. 10 clientes = 10 intervenções de DBA.
- **Deliverables:** `/super-admin` isolado, Wizard "Gerar Nova Organização", Painel de Tenant Health, `tenant_billing_events` (INV-1), `system_audit_log` exposto.

### Phase 9.3 — Auditor Reativo ✅ CONCLUÍDA

- **Data:** 2026-03-23
- **Deliverables:** `VerdictEvidence` VO (SHA-256), Máquina de estados no ledger (RECOMMENDED -> APPLIED/REJECTED), `sanction_review_queue` via trigger, `AuditorQueueScreen` Realtime, Testes Manuais (MT-9.3.1 a MT-9.3.10) aprovados.

### Phase 9.4 — ROI Dashboard & Precision Onboarding ✅ CONCLUÍDA

- **Data:** 2026-03-24
- **Destaques:** Dashboard Executivo (KPI Modular), CNPJ Auto-fill (ReceitaWS), Shadow Mode ROI simulator, Correção INV-4 (ShadowModeSimulation tipado).

### Phase 9.5 — Vínculo Dinâmico & UX do Operador ✅ CONCLUÍDA

- **Data:** 2026-03-25
- **Deliverables:** SLA Template Library, Smart Defaults (SQL), ServiceManifest decoupled logic.

### Phase 9.6 — Security & Data Foundation (The Shield) ✅ CONCLUÍDA

- **Data:** 2026-03-27
- **Highlights:** Edge Proxy (service_role removal), SuperAdmin MFA (TOTP), Lockout RPC, RLS Hardening (100% tables), Multi-level Auth (JWT hook), Entity Alias Mapping, Full PT-BR Localization, WCAG Contrast Overhaul, Coordinate Masking (Nominatim), WASM Build Hygiene.

### Phase 9.7 — Core Forensic Intelligence (The Brain) ✅ CONCLUÍDA

- **Data:** 2026-03-28
- **Deliverables:** Kinematic Guard (INV-17) triggering `KINEMATIC_ANOMALY` on-chain · `AlertFinancialImpact` VO with R$ real-time impact · GeoMath consolidation · `GeofenceEvidenceMap` visual snapshots · SLA Creation 3-Step Wizard · Industrial Deep Theme (Slate-950/800).
- 14 new tests · Dark Sync across all drawers · Geo-coordinate forensic hash (INV-7).

---

## Phase 10 — CI/CD & Launch Preparation

### Phase 10.1 — Schema Lock & Migration Freeze ✅ CONCLUÍDA

- **Data:** 2026-03-24
- 73 migrations auditadas · CI append-only guard (pr_scanner.sh) · schema_lock_v1.md.
- Security hardening migration `20260413000001` incluída.
