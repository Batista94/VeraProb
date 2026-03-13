# BusFlow: Strategic Context & Business Architecture Bootstrap

This document serves as the canonical entry point for any engineering session, AI agent, or product stakeholder interacting with the BusFlow repository. It defines the platform's true north: its business purpose, market differentiators, and operational rules.

---

## 1. Platform Purpose & The "Core" Vision
BusFlow is an **Automated SLA Compliance & Financial Protection Platform**. 
Its primary objective is to eliminate the gap between a signed B2B contract and physical operation execution. It acts as an impartial, automated "Judge" that ingests real-world events, evaluates them against strict contractual rules, and generates immutable financial projections (penalties or approvals).

While the current MVP (Vertical 1) is applied to **Corporate Charter and Shuttle Services (Fretamento)**, the CORE engine is industry-agnostic. It is designed to be easily replicated to other verticals (Construction Logistics, Facilities Management, Waste Collection) where SLA breaches result in financial loss.

## 2. Market Positioning & Differentiators

### The Basics (Table Stakes - What everyone has)
- Digital contract registry and basic route/zone mapping.
- GPS telemetry ingestion.
- Standard billing reports (Planned vs. Executed).

### The Advanced (What makes us highly competitive)
- **Strict Multi-Tenant Isolation:** Complete data privacy. A contractor (Client A) cannot see the zones, routes, or assets of another contractor (Client B), enforced at the database level.
- **Just-in-Time (JIT) Master Data:** "Zero-Friction UX" that allows dispatchers to create operational assets (like Geofences) *inline* during contract creation, without breaking their workflow.
- **Dynamic SLA Templates:** Reusable rule sets (e.g., "15-min tolerance for arrival", "100% penalty for no-show") that can be attached to any contract.

### The "Blue Ocean" (Unaddressed Pain Points - Our True Gold)
- **The Burden of Proof (Immutable Ledger):** In B2B, disputes over SLA breaches take weeks of email back-and-forth. BusFlow generates *cryptographic-like proof* of execution. If a penalty is applied, the system provides an irrefutable, unalterable trail of exactly *why*, *when*, and *where* it failed.
- **Predictive Penalty Alerting (Future):** Instead of reporting a failure at the end of the month, the system warns the operator *before* the breach (e.g., "Vehicle is delayed; SLA breach and $500 penalty in 4 minutes. Take action.").
- **Client Transparency Portal (Future):** Giving the end-client a restricted view of their own SLAs, eliminating the need for the operator to manually generate compliance reports.

## 3. End-to-End Business Rules & Lifecycle
Every contract in the platform follows a strict, end-to-end lifecycle. Engineering decisions must respect this flow:

### Phase A: Negotiation & Setup (The Rules)
1. **Contractor Onboarding:** The client (tenant's customer) is registered.
2. **Zone Mapping:** Physical locations (garages, client gates) are mapped via Geofencing. Zones can be *Global* (owned by the operator) or *Exclusive* (tied strictly to a specific Contractor).
3. **Contract Drafting:** A digital contract is created, linking the Contractor, the Operational Zones (Routes/Plans), and the Financial Rules (SLA Templates and Penalties).

### Phase B: Execution & Telemetry (The Real World)
1. **Shift Projection:** The system projects exactly what *should* happen today based on the contract (e.g., Bus must arrive at Zone X at 08:00 AM).
2. **Ingestion:** Telemetry (GPS, check-ins) flows into the system. 
3. **Normalization:** The system cleans the noisy data (GPS bounces) into deterministic events (e.g., `ENTERED_ZONE_X`).

### Phase C: The Evaluation Engine (The Judge)
1. The Engine compares Phase B (Reality) against Phase A (The Rules).
2. **Idempotency:** The Engine is deterministic. Running the same physical event against the same rule will always yield the exact same financial result.

### Phase D: Adjudication & Settlement (The Ledger)
1. **Immutable State:** The Engine outputs a verdict (e.g., `COMPLIANT` or `BREACHED_DELAY`).
2. **Financial Impact:** If breached, the specific financial penalty is automatically calculated and recorded in an append-only ledger. No `UPDATE` or `DELETE` is permitted.
3. **Billing Output:** At the end of the cycle, the aggregated ledger generates the indisputable invoice and compliance report.

## 4. Architectural Invariants (Business-Driven)
To support the business goals, the architecture must strictly enforce:
- **Domain Sovereignty:** The business logic (SLA rules, penalty calculation) is completely isolated from the UI and external APIs.
- **Read-only OCC (Operations Control Center):** Human dispatchers can monitor and acknowledge issues, but they *cannot* edit the historical execution state to hide a breach.
- **Integer Finance:** All currency is handled using integer cents to prevent floating-point rounding errors during penalty calculations.

## 5. Technology Stack Summary
*(For AI Agents: Do not violate these constraints during implementation)*
- **Frontend:** Flutter (Mobile/Web) + Riverpod (State Management)
- **Backend/DB:** Supabase (PostgreSQL) with strict Row-Level Security (RLS) and custom JWT Hooks for Tenant Isolation.

## 6. Governance Model & AI Personas
The Engineering Council reviews all code to ensure it aligns with the business vision:
- **Chief Architect:** Ensures the "CORE" remains industry-agnostic and modular.
- **Senior Engineer:** Enforces Clean Architecture and framework best practices.
- **UX Director:** Defends the "Zero-Friction" and "Just-in-Time" operator experience.
- **QA Lead:** Guarantees Tenant Isolation (data security) and Ledger Immutability.

## 7. Current System State
- **Phase 0 to 4:** (Completed) - Base stabilization, Engine Rules, Immutable Ledger foundation.
- **Phase 5 (B2B Refactoring):** (In Progress)
  - **Sprint 5.11:** (Completed) - Wizard refactoring, Contract Cloning, SLA Templates.
  - **Sprint 5.12:** (In Progress) - "Just-in-Time" master data creation (Zero-Friction UX) and strict Tenant Isolation on search fields.
- **Phase 6 (Admin & Master Data):** (Planned) - Contractor aggregates, RBAC (Gerente vs. Operador profiles).