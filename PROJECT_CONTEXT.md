# PactaFlow: Strategic Context & Business Architecture

This document serves as the **canonical entry point** for any engineering session, AI agent, or stakeholder. It defines the platform's "True North": its business purpose, market differentiators, and operational rules.

---

## 1. Platform Purpose: The "Digital Judge"
PactaFlow is an **Automated SLA Compliance & Financial Protection Platform**. 
It eliminates the gap between a signed B2B contract and physical operation execution. It acts as an impartial "Judge" that:
1. **Ingests** real-world telemetry (GPS, Check-ins).
2. **Normalizes** noisy data into deterministic facts.
3. **Evaluates** facts against strict contractual rules.
4. **Verdicts** financial impacts (penalties/approvals) into an **Immutable Ledger**.

---

## 2. Market Differentiators (Strategic Moat)

*   **Financial Shield (INV-2):** We don't just report delays; we manage the **Relative Risk** of the entire operation. By setting financial ceilings and calculating exposure in real-time, we protect the operator's margin against catastrophic penalization.
*   **The Burden of Proof:** PactaFlow generates *cryptographic-like proof* of execution. disputes are resolved by data, not emails.
*   **Zero-Friction JIT Master Data:** Dispatchers can create operational assets (Geofences, Zones) *inline* during contract creation. The system adapts to the user, not the other way around.
*   **Multi-Tenant Sovereignty:** Complete data isolation enforced at the database level (RLS). Client A never exists in the context of Client B.

---

## 3. Core Architectural Invariants
*   **IMMUTABLE LEDGER:** No UPDATE/DELETE on financial facts.
*   **FINANCIAL PRECISION:** All currency as `BIGINT` cents via `Money` VO.
*   **UTC EVERYWHERE:** Single timezone for all backend and logic operations.
*   **DOMAIN SOVEREIGNTY:** Pure Dart business logic, zero infrastructure dependencies.
*   **DETERMINISTIC ENGINE:** Replaying events against rules must always yield the same result.

---

## 4. The Engineering Council
All non-trivial changes must be reviewed by the specialized personas in `docs/council/`:
- **architect:** Structural integrity and Clean Architecture.
- **senior_engineer:** Performance and implementation details.
- **qa_security:** RLS, tenant isolation, and auditability.
- **ux_operations:** Operator efficiency and "Zero-Friction" UX.
- **business_maverick:** Market value, ROI, and competitive edge.

---

## 5. Deployment & Tools
*   **Skills:** Specialized agent capabilities are located in `.claude/skills/`.
*   **Database:** Supabase/PostgreSQL with migrations managed via SQL Editor (Bootstrap Phase).
*   **Execution:** Flutter Web (OCC console).

---

## 6. Project Roadmap State (Q1 2026)
*   **Phase 5 (B2B Refactoring):** **CONCLUÍDA**. 
    *   *Feitos:* SLA Templates, Contract Cloning, JIT Zones/Contractors, Teto Financeiro e Grace Period.
*   **Phase 6 (Administration & Assets):** **CONCLUÍDA** (Sub-blocos 1-8).
    *   *Implementado:* Advanced RBAC, Custom JWT Claims (Org ID), Dashboard Consolidado, Convites de Usuários, Aprovação de Contratos e **Asset Manager** (Drivers, Routes, Vehicles com isolamento RLS).
*   **Phase 6.5 (Ingestion & Resilience):** **CONCLUÍDA**.
    *   *Realizado:* Ingestão resiliente (Sascar/Omnitracs), Anti-Corruption Edge, Chaos Tolerance (Late Arrival, Ordering), Asset State Machine e Kinematic Filtering.
*   **Phase 7 (Evidence & Audit):** **CONCLUÍDA**.
    *   *Feitos:* Audit Sealing (INV-16/17), Prova de Execução (Audit Packages), Dashboards Executivos e Portal do Contratante.
*   **Phase 7.5 (Financial Defense & Shadow Mode):** **CONCLUÍDA**. 
    *   *Implementado:* Shadow Mode (ROI Simulator), Tribunal de Apelações e Hardening Forense DB-level. 568 testes operando. ✅
*   **Phase 8.8 (Telemetry Integrity & Anti-Spoofing):** **CONCLUÍDA**. 
    *   *Realizado:* Detecção ativa de Fake GPS (Haversine Variance), Audit Trail imutável com SHA-256 e Invariante 21 (bloqueio automático de suspeitas). ✅

---
*Last updated: March 19, 2026 — Phase 8.8 (Telemetry Integrity & Anti-Spoofing)*
