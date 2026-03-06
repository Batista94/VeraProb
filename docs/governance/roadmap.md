# BusFlow B2B Strategic Roadmap

## [x] Phase 0: Core Stabilization
- [x] Fix synchronous read violation (`UnimplementedError`) in `PostgresAuditService`.
- [x] Resolve Supabase `ClientException` (Fetch URL/CORS) in ledger queries.
- [x] Fix real-time consistency bug (Vehicles in sidebar but missing on `FleetMap`).
- [x] Implement global `ErrorBoundary` widget to prevent top-level application crashes.

## [x] Phase 1: Multi-Tenancy & Auth Foundation
- [x] Create Multi-Tenant architecture document defining RLS and tenant boundaries.
- [x] Create SQL Migration file (`organizations` table, HASH partitioning on ledger, RLS policies, Custom JWT hook).
- [x] Add `organizationId` isolation column to `AuditLog` domain entity and DTO logic.
- [x] Implement Supabase Auth (Substitute the static 4-digit PIN for JWT login).
- [x] Connect `AuthService` to fetch standard user profiles upon successful Supabase JWT challenge.
- [x] Replace `admin_pin_service` references in the presentation layer.
- [x] **Validation:** Run Multi-Tenant Validation Scenarios (Dual Org, Cross-Tenant access, Integrity logic).

## [x] Phase 2: Contract Rules & Configurable Determinism
- [x] **Design:** Define `ContractualRule` entity and rules-versioning state model.
- [x] **Design:** Architect the temporal evaluation context (Rule Replay).
- [x] **Council Review:** Validate deterministic safety and isolation.
- [x] **Implementation:** Update Postgres Schema (`contract_rule_sets`, `contract_rule_versions`).
- [x] **Implementation:** Build Domain Models (`ContractualRule`, `RuleSnapshot`).
- [x] **Implementation:** Update `PlanDeclaration` and Repositories to handle Snapshots.
- [x] **Implementation:** Update `ContractualEvaluationEngine` to dynamically invoke rules.
- [x] **Implementation:** Basic rules Administration logic (Services).
- [x] **Validation:** Rule Replay Integrity & Scenario simulations.

## [x] Phase 3: Explainability & Investigation
- [x] **Design:** Architectural specification for Evaluation Traces and Investigation Console.
- [x] **Council Review:** Validate trace schema, OCC integration, and causal linkage.
- [x] **Infrastructure:** SQL migration for `contractual_evaluation_traces` (append-only, RLS).
- [x] **Domain:** `EvaluationTrace`, `EvaluationDecision`, `EngineEvaluationResult` entities.
- [x] **Application:** Refactor `ContractualEvaluationEngine` to emit deterministic traces.
- [x] **Persistence:** Postgres and In-Memory trace repositories with causal ledger linkage.
- [x] **Provider:** `evaluationTraceRepositoryProvider` with persistence mode toggle.
- [x] **Presentation:** OCC `InvestigationModal` with ledger timeline, decision cards, and evidence display.
- [x] **Validation:** Phase 3 Compliance Review — all 8 tests pass.

## [ ] Phase 4: Operational Proactivity & Alerts
- [ ] Define `AlertTriggeredEvent` and create `active_alerts` projection table.
- [ ] Integrate alerts into the OCC sidebar with triage workflows.
- [ ] Implement realtime notification streams for critical SLA violations.

## [ ] Phase 5: Reporting & Financial Exports
- [ ] Implement async PostgreSQL aggregation pipelines (pg_cron) for monthly compliance and financial exports.
- [ ] Build CSV/PDF export engine for audit-ready documentation.
- [ ] Create "Executive Dashboard" for high-level SLA performance tracking.

## [ ] Phase 6: Administration & Tenant Onboarding
- [ ] Build "Organization Management" UI for creating and managing tenants.
- [ ] Implement "Rule Configuration Studio" for visual SLA parameter editing.
- [ ] Create Asset & User onboarding workflows (Invite System, Role Management).

## [ ] Phase 7: Operational Hardening
- [ ] Establish Environment Separation (Dev/Staging/Prod) with CI/CD pipelines.
- [ ] Implement system observability (Sentry integration, Postgres performance monitoring).
- [ ] Conduct final security penetration testing and RLS audit at scale.
