# BusFlow: Project Context Bootstrap

This document serves as the canonical entry point and bootstrap context for any engineering session or AI agent interacting with the BusFlow repository. It provides a map of the platform's purpose, architecture, and governance.

---

## 1. Platform Purpose
BusFlow is an **event-driven operational intelligence platform** designed for monitoring and auditing contractual transportation operations. It transforms raw physical telemetry (GPS/IoT) into verifiable contractual truth and immutable financial projections, ensuring operational determinism for B2B shuttle and charter services.

## 2. Core Architecture (The Operational Pipeline)
The system follows a strict linear pipeline to guarantee data integrity:

**Event Ingestion** (GPS/State)  
→ **Normalization** (Smoothing/Deduplication)  
→ **Subscriber** (Stream Dispatcher)  
→ **Evaluation Engine** (Contractual Logic)  
→ **Immutable Ledger** (System of Record)  
→ **Execution States** (Operational Truth)  
→ **Financial Snapshots** (Margin Projection)  
→ **Query Services** (Read Models)  
→ **Operations Control Center (OCC)** (Real-time Monitoring & Investigation)

## 3. Architectural Invariants
- **Immutable Event Ledger:** All operational events are append-only. No `UPDATE` or `DELETE` allowed.
- **Deterministic Evaluation Engine:** Logic executes pure algorithms based on fixed parameters to ensure reproducible results.
- **Financial Precision:** Currency is handled using **integer cents** (BIGINT) to avoid floating-point errors.
- **Domain Sovereignty:** Business logic is isolated from infrastructure and UI (DDD).
- **Read-only OCC:** The Command Center monitors and acknowledges; it never alters historical execution state.
- **Idempotent Event Processing:** Redundant events are ignored by the engine without side effects.

## 4. Technology Stack
- **Frontend:** Flutter (Mobile/Web)
- **State Management:** Riverpod
- **Backend-as-a-Service:** Supabase
- **Database:** PostgreSQL (with RLS, HASH Partitioning, and custom JWT Hooks)
- **Realtime:** WebSockets/WAL Replication for telemetry and OCC updates.

## 5. Multi-Tenant Model
Isolation is enforced from the bottom up via the `organization_id`. 
- **DB Boundary:** PostgreSQL Row-Level Security (RLS) policies restrict data access based on the `org_id` claim in the user's JWT.
- **Compute Boundary:** The Evaluation Engine resolves rule configurations based on the tenant's context.

## 6. Governance Model
The Engineering Council enforces a strict development lifecycle. This council is composed of specialized AI personas that review every design and implementation:
- **Chief Architect:** Structural integrity, DDD, and core vs. module separation.
- **Senior Engineer:** Tech stack (Flutter/Riverpod/Supabase), Clean Architecture, and performance.
- **UX & Operations Director:** Human-system interaction, OCC workflows, and provenance.
- **QA & Security Lead:** RLS enforcement, tenant isolation, and idempotency.

The lifecycle consists of:
1. **Design Specification** (Architectural Draft)
2. **Council Review** (Validation of Invariants)
3. **Implementation** (Code Execution)
4. **Validation** (E2E/Scenario Testing)
5. **Compliance Report** (Durable Proof of Work)

## 7. Current System State
- **Phase 0 to 4:** (Completed) - Stabilization, Multi-Tenancy, Rules Engine, Investigation Traces, and Operational Alerts.
- **Phase 5: Contract & Plan Lifecycle (B2B Refactoring):** (In Progress) - Design and Code implementation finished. Currently executing **Trilha B (UI/UX Standardization & Dashboard Pivot)** before commencing manual validation (Phase 5.10).
- **Phase 6: Admin & Tenant Self-Service** (Planned) - RBAC, invitations, and asset onboarding.
- **Phase 7: Evidence & Audit Exports** (Planned) - Compliance aggregation and CSV/PDF exports.

## 8. Documentation Map
For deeper technical details, refer to the `docs/` hierarchy:
- [`docs/council`](./docs/council/): AI Persona definitions (Architect, Senior Engineer, UX Director, QA Lead).
- [`docs/architecture`](./docs/architecture/): System overview, pipeline details, and feature designs (01 to 09).
- [`docs/governance`](./docs/governance/): Framework, B2B strategy, and the Strategic Roadmap.
- [`docs/governance/compliance`](./docs/governance/compliance/): Validation reports and security audits.
- [`docs/runbooks`](./docs/runbooks/): Database bootstrap and operational testing procedures.
