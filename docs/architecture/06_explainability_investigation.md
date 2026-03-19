# Phase 3 Design Specification: Explainability & Investigation

## 1. Goal Description
The objective of Phase 3 is to evolve VeraProb from a "Black Box Evaluator" into an explainable auditing platform. When the `ContractualEvaluationEngine` makes a decision (e.g., assessing a penalty or approving a trip), it must provide a cryptographic linkage between the input telemetry, the parameters applied, and the final judgment. This capability allows human operators in the Operations Control Center (OCC) to forensicly investigate and justify system decisions.

## 2. Core Architectural Concepts

### 2.1 Separation of Projections and Explainability Artifacts
Evaluation traces are investigative artifacts and must **not** be embedded directly into domain projection tables like `contractual_execution_states` or `contractual_financial_snapshot`. Instead, traces are persisted in a dedicated, append-only investigation structure `contractual_evaluation_traces`. This isolation ensures that execution states remain clean and stable, deterministic replay remains safe, and OCC workflows can scale independently without duplicating traceability data.

### 2.2 Engine Version Traceability
To ensure future audits can identify exactly which algorithm produced a judgment, the trace must record the version of the `ContractualEvaluationEngine` responsible for the decision. This ensures that historical decisions remain fully explainable, even as internal algorithms evolve.

### 2.3 Deterministic Rule Evaluation 
The evaluation engine guarantees a deterministic execution order based on rule priority, using the rule identifier as a deterministic tie-breaker. Each decision inherently documents the exact priority and identifier to prove that the evaluation sequence is structurally reproducible during any ledger replay.

### 2.4 Evidence Integrity
Decisions must capture both the contextual inputs (the parameters deployed) and the raw quantitative evidence evaluated. Traces must reference the originating ledger event that triggered the evaluation, enabling the OCC to reconstruct the causal timeline.

### 2.5 Engine Responsibility
The `ContractualEvaluationEngine` is structurally responsible for producing the trace automatically during processing. The engine will emit a triplet of outputs for each evaluation step:
1. The resulting **execution state**
2. The **financial impact** produced (if any)
3. The **evaluation trace** explaining the decision

## 3. Data Structure Definition

### Database Updates
**Table: `contractual_evaluation_traces`** (NEW)
- `id` (UUID, Primary Key)
- `organization_id` (UUID, Tenant Isolation)
- `entity_id` (String) (e.g., Trip ID or Service Execution Token)
- `triggering_event_id` (UUID, Foreign Key to `sla_audit_ledger`)
- `evaluated_at_utc` (Timestamp)
- `engine_version` (String)
- `decisions_jsonb` (JSONB)

### JSON Structure: `decisions_jsonb`
```json
[
  {
    "rule_id": "uuid-v4",
    "rule_type": "MIN_GEOFENCE_COVERAGE",
    "rule_version": 2,
    "rule_priority": 1,
    "outcome": "PASS",
    "evidence": {
       "required_dwell_seconds": 60,
       "actual_dwell_seconds": 120
    }
  },
  {
    "rule_id": "uuid-v4",
    "rule_type": "MAX_TOLERANCE_DELAY",
    "rule_version": 1,
    "rule_priority": 2,
    "outcome": "PENALTY",
    "financial_impact_cents": 5000,
    "evidence": {
       "allowed_delay_minutes": 10,
       "actual_delay_minutes": 15
    }
  }
]
```

## 4. Proposed Implementation Steps

### Domain Layer
#### `lib/domain/sla_audit/evaluation_trace.dart` (NEW)
Domain entity representing `EvaluationTrace` and `EvaluationDecision`.
#### `lib/domain/sla_audit/engine_evaluation_result.dart` (NEW)
A wrapper explicitly returning the triplet: `ContractualExecutionState`, `ContractualFinancialSnapshot` (if impacted), and `EvaluationTrace`.

### Application Layer
#### `lib/application/sla_audit/contractual_evaluation_engine.dart` (MODIFY)
Refactor the evaluation algorithm to return `EngineEvaluationResult`. Implement deterministic sorting of rules by priority/ID tie-breaking, and capture exact evidence, triggering event references, and the engine version.

### Infrastructure Layer
#### `supabase/migrations/XXX_explainability_traces.sql` (NEW)
Create the `contractual_evaluation_traces` table with RLS policies scoped to `organization_id` and indices geared towards timeline retrieval via `entity_id`.
#### `lib/infrastructure/sla_audit/postgres_evaluation_trace_repository.dart` (NEW)
Implementation for persisting and querying the independent trace structures.

### Presentation Layer (OCC)
#### `lib/features/occ/presentation/widgets/investigation_modal.dart` (NEW)
A component querying the trace repository independently alongside projections to visually bridge execution states and telemetry events.

## 5. Verification Plan
1. **Engine Triplet Integrity:** Run unit tests forcing varying evaluations. Assert the engine accurately returns the `EngineEvaluationResult` triplet and trace with valid engine version, priority sorting, and deterministic evidence.
2. **Persistence Validation:** Ensure the `EvaluationTrace` is isolated into `contractual_evaluation_traces`, completely divorced from the domain execution records, while correctly referencing `triggering_event_id`.
3. **Investigation Workflow:** Retrieve traces and bind them to the Timeline Investigation UI, effectively uniting independent read models at the presentation boundary.
