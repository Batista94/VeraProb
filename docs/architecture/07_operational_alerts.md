# Phase 4 Design Specification: Operational Alerts

## 1. Goal Description

Phase 4 introduces a domain-level alert system derived from the deterministic evaluation pipeline. When the `ContractualEvaluationEngine` produces a contractual decision that requires operator attention — such as a NoShow, EvidenceGap, or financial penalty — the system must emit a structured `OperationalAlert` that is persisted, tenant-scoped, and surfaced in the OCC for triage.

This is distinct from the existing trip-level "attention state" (`AlertBar`, `AlertsTriadeDrawer`), which operates on realtime telemetry. Operational alerts are **derived from contractual evaluation outcomes** and represent auditable, persistent signals.

## 2. Alert Derivation Model

### Trigger Points

Alerts are derived as side-effects of execution state transitions in `_commitEvaluationResults`:

| Execution Transition | Alert Type | Severity |
|---|---|---|
| `pending → noShow` | `NO_SHOW` | CRITICAL |
| `pending → evidenceGap` | `EVIDENCE_GAP` | WARNING |
| `pending → executed` (with penalty decisions) | `PENALTY_APPLIED` | HIGH |

> [!IMPORTANT]
> Alerts are **not** triggered directly from telemetry. They are produced exclusively by the evaluation engine after a contractual decision is made. This preserves the Single Decision Engine invariant.

### Derivation Pipeline

```
Evaluation Engine produces state transition
→ _commitEvaluationResults persists ledger + trace
→ Alert derived from transition outcome
→ OperationalAlert persisted to alert table
→ OCC queries active alerts via provider
```

## 3. Domain Entity: `OperationalAlert`

```dart
class OperationalAlert extends Equatable {
  final String id;                  // UUID
  final String organizationId;     // Tenant isolation
  final String entityId;           // SET ID
  final String contractId;
  final String alertType;          // NO_SHOW | EVIDENCE_GAP | PENALTY_APPLIED
  final String severity;           // CRITICAL | HIGH | WARNING
  final DateTime triggeredAtUtc;
  final String? triggeringEventId; // Ledger event UUID (causal link)
  final String? traceId;          // EvaluationTrace UUID (explainability link)
  final Map<String, dynamic> context; // Alert-specific metadata
  final String status;             // ACTIVE | ACKNOWLEDGED | RESOLVED
  final DateTime? acknowledgedAtUtc;
  final String? acknowledgedByUserId;
  final DateTime? resolvedAtUtc;   // Audit trail: resolution timestamp
}
```

### Alert Lifecycle

```
ACTIVE → ACKNOWLEDGED → RESOLVED
```

- **ACTIVE**: Alert is emitted and requires operator attention.
- **ACKNOWLEDGED**: Operator has reviewed and accepted the alert.
- **RESOLVED**: Alert no longer requires action (e.g., after investigation).

> [!WARNING]
> Acknowledgment and resolution are **operator-only actions** executed through `AlertService` in the application layer. The service enforces tenant ownership, valid lifecycle transitions, and audit timestamps. The repository exposes no arbitrary status mutation — lifecycle transitions are strictly service-controlled.

## 4. Alert Severity Levels

| Severity | Color | Description |
|---|---|---|
| CRITICAL | `VeraProbColors.critical` | Immediate contractual breach requiring operator action |
| HIGH | `VeraProbColors.delayed` | Financial penalty applied, needs review |
| WARNING | `VeraProbColors.warning` | Incomplete evidence, manual investigation recommended |

## 5. Storage Model

### SQL Table: `operational_alerts`

```sql
CREATE TABLE operational_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  entity_id TEXT NOT NULL,
  contract_id TEXT NOT NULL,
  alert_type TEXT NOT NULL,
  severity TEXT NOT NULL,
  triggered_at_utc TIMESTAMPTZ NOT NULL DEFAULT now(),
  triggering_event_id UUID REFERENCES sla_audit_ledger_v2(id),
  trace_id UUID REFERENCES contractual_evaluation_traces(id),
  context JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  acknowledged_at_utc TIMESTAMPTZ,
  acknowledged_by_user_id UUID,
  resolved_at_utc TIMESTAMPTZ,
  
  CONSTRAINT valid_alert_type CHECK (alert_type IN ('NO_SHOW', 'EVIDENCE_GAP', 'PENALTY_APPLIED')),
  CONSTRAINT valid_severity CHECK (severity IN ('CRITICAL', 'HIGH', 'WARNING')),
  CONSTRAINT valid_status CHECK (status IN ('ACTIVE', 'ACKNOWLEDGED', 'RESOLVED')),
  CONSTRAINT unique_alert_per_event UNIQUE (triggering_event_id, alert_type)
);

-- Tenant isolation
ALTER TABLE operational_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "org_isolation_select" ON operational_alerts
  FOR SELECT USING (organization_id = auth.jwt() ->> 'organization_id');
CREATE POLICY "org_isolation_insert" ON operational_alerts
  FOR INSERT WITH CHECK (organization_id = auth.jwt() ->> 'organization_id');

-- Triage queries: active alerts by organization, ordered by severity then time
-- Supports OCC sort: CRITICAL first, then HIGH, then WARNING, most recent first
CREATE INDEX idx_alerts_active ON operational_alerts (organization_id, status, severity, triggered_at_utc DESC);
-- Entity lookup for investigation correlation
CREATE INDEX idx_alerts_entity ON operational_alerts (entity_id, triggered_at_utc DESC);
```

## 6. Repository Interface

```dart
abstract class OperationalAlertRepository {
  Future<String> save(OperationalAlert alert);       // Returns generated UUID
  Future<List<OperationalAlert>> findActive(String organizationId);
  Future<List<OperationalAlert>> findByEntityId(String entityId);
  Future<OperationalAlert?> findById(String alertId);
}
```

## 7. Application Layer: Alert Derivation

The `ContractualEvaluationEngine._commitEvaluationResults` will be extended to call a new `AlertDerivationService` after persisting the ledger entry and trace:

```dart
// Inside _commitEvaluationResults, after trace persistence:
final alert = AlertDerivationService.deriveFrom(
  state: updatedState,
  decisions: decisions,
  triggeringEventId: eventId,
  traceId: traceId,
);
if (alert != null) {
  await _alertRepo.save(alert);
}
```

### Idempotency Guarantee

Idempotency is anchored to the **triggering ledger event**, not `entityId + alertType`. The rule is:

```
(triggering_event_id, alert_type) must be unique
```

Only one alert of a given type may originate from the same ledger event. This preserves replay safety without suppressing legitimate repeated alerts across different evaluations. Enforced at the database level via a `UNIQUE` constraint.

## 8. OCC Alert Visualization

### Alert Panel (replaces current `AlertsTriadeDrawer` for contractual alerts)

The existing `AlertsTriadeDrawer` handles realtime trip attention. A new **Contractual Alerts Panel** will be added to the OCC, accessible from a dedicated tab or panel:

- **Active alert list** — sorted by severity (CRITICAL first), then by time
- **Alert card** — shows SET ID, contract, alert type, severity badge, time, and "Investigar" action
- **Acknowledge button** — calls `AlertService.acknowledge()`
- **Link## 8.1 Alert Lifecycle Service

All lifecycle transitions are enforced through `AlertService`:

```dart
class AlertService {
  Future<void> acknowledge(String alertId, String userId, DateTime atUtc);
  Future<void> resolve(String alertId, DateTime atUtc);
}
```

The service validates tenant ownership and valid transitions (ACTIVE→ACKNOWLEDGED→RESOLVED).

## 9. OCC Investigation Integration

Alerts provide direct navigation to the Phase 3 investigation interface:

```
Operator sees active alert in OCC
→ Reviews alert severity and context
→ Taps "Investigar" to open InvestigationModal for causal reconstruction
→ Resolves alert when action is complete
```

## 9. Tenant Isolation & Invariants

| Invariant | Enforcement |
|---|---|
| Tenant isolation | RLS on `operational_alerts`, `organization_id` filter on all queries |
| Idempotency | Duplicate alert suppression by `entityId` + `alertType` |
| Domain sovereignty | `OperationalAlert` is pure Dart, no Flutter dependencies |
| Single decision engine | Alerts derived only from engine evaluation results |
| Read-only OCC | Alert acknowledgment delegated to `AlertService`, not OCC |
| Causal linkage | Alerts reference `triggeringEventId` and `traceId` |

## 10. Proposed Implementation Steps

### Domain Layer
#### [NEW] `lib/domain/sla_audit/operational_alert.dart`
#### [NEW] `lib/domain/sla_audit/operational_alert_repository.dart`

### Application Layer
#### [NEW] `lib/application/sla_audit/alert_derivation_service.dart`
#### [NEW] `lib/application/sla_audit/alert_service.dart`
#### [MODIFY] `lib/application/sla_audit/contractual_evaluation_engine.dart`

### Infrastructure Layer
#### [NEW] `supabase/migrations/2026XXXXXXXX_operational_alerts.sql`
#### [NEW] `lib/infrastructure/sla_audit/postgres_operational_alert_repository.dart`
#### [NEW] `lib/infrastructure/sla_audit/in_memory_operational_alert_repository.dart`

### Provider Layer
#### [NEW] `lib/state/providers/alert_providers.dart`

### Presentation Layer
#### [NEW] `lib/features/admin/presentation/command_center/widgets/contractual_alerts_panel.dart`
#### [MODIFY] `lib/features/admin/presentation/command_center/command_center_screen.dart`

## 11. Verification Plan

### Automated Tests
- Alert derivation from NoShow, EvidenceGap, and Penalty transitions
- Idempotency: duplicate evaluation does not produce duplicate alerts
- Alert lifecycle: ACTIVE → ACKNOWLEDGED → RESOLVED
- Tenant isolation: alerts scoped by `organization_id`
- Causal linkage: alerts reference correct `triggeringEventId` and `traceId`

### Manual Verification
- OCC shows active contractual alerts
- Alert triage workflow: review → investigate → acknowledge → resolve
- Alerts filter by severity and time
