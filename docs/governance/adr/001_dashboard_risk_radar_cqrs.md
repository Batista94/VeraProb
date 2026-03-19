# ADR 001: Pivot for Dashboard Contractual Risk Radar (CQRS)

**Date:** 2026-03-10
**Status:** Accepted
**Context:** Trilha B3 (Dashboard Pivot)

## Context
The VeraProb Operations Control Center (OCC) dashboard originally featured a real-time, icon-heavy Heatmap (`HeatmapSection`). The UX/Operations Council identified that this visual approach caused high cognitive load for B2B shuttle operators, who need to focus on contractual obligations (Shift Patterns) and financial impact, rather than geographical commodity maps. 

## Alternatives Considered
- **Keep Heatmap & Enhance Filters:** Adds complexity but does not solve the root issue that maps prioritize "where" over "how much" (financial impact).
- **Direct Repositories Aggregation in Dashboard:** Fetching raw `ContractualServiceExecution` and `OperationalAlert` entries and aggregating them directly in the UI. Rejected by the Architect Persona as it violates Domain Sovereignty and CQRS standards.

## Decision
We will replace the `HeatmapSection` with a **Contractual Risk Radar**. 
From an architectural standpoint, this component MUST be strictly a **Read Model**. It will consume a new unified projection provider (`dashboardRiskFeedProvider`) that aggregates existing projections (`timelineProjectionProvider` and `activeAlertsProvider`) without ever accessing the `EvaluationEngine` or Primary Write Repositories.

## Consequences
- **Positive:** Improved B2B UX (CFO metrics at a glance), strict adherence to CQRS, decoupling of UI and domain state, reduction of unnecessary map rendering overhead.
- **Security Constraint (QA enforced):** The newly created `dashboardRiskFeedProvider` must strictly adhere to Tenant Isolation via Postgres RLS. It cannot bypass `organization_id` filters, minimizing the risk of multi-tenant data leakage on the main screen.

*Approved by the Engineering Council.*
