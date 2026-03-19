# Phase 3 Compliance Report — Explainability & Investigation

**Date:** 2026-03-05  
**Engine Version:** `VeraProb-core_v3`  
**Phase Status:** ✅ Operationally Complete

---

## Compliance Verification Matrix

| Invariant | Test ID | Result |
|---|---|---|
| Immutable Event Ledger | — | ✅ `REVOKE UPDATE, DELETE` on `contractual_evaluation_traces` |
| Deterministic Replay | C3-04 | ✅ Identical inputs → identical trace decisions |
| Tenant Isolation | — | ✅ RLS policies enforce `organization_id` on SELECT/INSERT |
| Domain Sovereignty | C3-07 | ✅ Pure Dart models, round-trip serialization |
| Single Decision Engine | C3-08 | ✅ Traces produced exclusively by `ContractualEvaluationEngine` |
| Query Tenant Scoping | — | ✅ All queries filter by `organization_id` |

---

## Automated Test Results

| Test | Description | Status |
|---|---|---|
| C3-01 | Binding evaluation persists exactly one trace | ✅ |
| C3-02 | Sweep NoShow evaluation persists a trace | ✅ |
| C3-03 | `triggeringEventId` matches persisted ledger UUID | ✅ |
| C3-04 | Identical inputs produce identical trace decisions | ✅ |
| C3-05 | All traces carry centralized engine version | ✅ |
| C3-06 | Each `EvaluationDecision` has all required fields | ✅ |
| C3-07 | `EvaluationTrace` is pure Dart (domain sovereignty) | ✅ |
| C3-08 | Repository exposes no update/delete operations | ✅ |

Test file: [phase3_compliance_test.dart](file:///c:/Projects/MVP%20-%20Bus/test/compliance/phase3_compliance_test.dart)

---

## Static Analysis

```
dart analyze lib → 0 errors (2 info-level pre-existing hints)
```

---

## OCC Investigation Flow

| Step | Verified |
|---|---|
| SLA Audit Screen → row tap → Detail Drawer | ✅ |
| Detail Drawer → "Investigar Decisão" → Investigation Modal | ✅ |
| Modal: Ledger timeline with chronological ordering | ✅ |
| Modal: Triggering event highlighted with "GATILHO" badge | ✅ |
| Modal: Decision cards with rule evidence and outcomes | ✅ |
| Modal: "SOMENTE LEITURA" read-only badge | ✅ |
| Modal: Graceful missing trace state | ✅ |

---

## Phase 3 Deliverables

| Artifact | Location |
|---|---|
| Design Specification | [06_explainability_investigation.md](file:///c:/Projects/MVP%20-%20Bus/docs/architecture/06_explainability_investigation.md) |
| SQL Migration | [20260305194500_explainability_traces.sql](file:///c:/Projects/MVP%20-%20Bus/supabase/migrations/20260305194500_explainability_traces.sql) |
| Domain Models | `evaluation_trace.dart`, `engine_evaluation_result.dart` |
| Repositories | `PostgresEvaluationTraceRepository`, `InMemoryEvaluationTraceRepository` |
| Providers | `investigation_providers.dart`, `sla_providers.dart` |
| OCC Widget | `investigation_modal.dart` |
| Compliance Tests | `phase3_compliance_test.dart` |
