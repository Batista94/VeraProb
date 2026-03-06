# Phase 5 Design Specification: Reporting & Financial Exports

## 1. Goal

Transform the immutable ledger and contractual financial snapshots into auditable reporting artifacts. Phase 5 builds export and aggregation capabilities on the existing daily snapshot infrastructure without modifying it.

## 2. Existing Infrastructure (No Changes)

| Component | Role |
|---|---|
| `ContractualFinancialDailySnapshot` | Immutable daily snapshot with reprocessing chain |
| `ContractualFinancialSnapshotGenerator` | Idempotent daily generation from execution states |
| `ContractualFinancialClosingService` | Automated daily closing orchestrator |
| `ContractualFinancialImpact` | Read model for OCC KPI dashboard |
| `SlaFinancialImpactScreen` | OCC financial KPI cards |

These remain untouched. Phase 5 layers **read-only aggregation and export** on top.

## 3. Financial Aggregation Model

### Billing Cycle Report

A billing cycle aggregates daily snapshots across a date range (typically monthly), per organization and optionally per contract.

```dart
class BillingCycleReport extends Equatable {
  final String id;                     // Deterministic: orgId + contractId + period
  final String organizationId;
  final String? contractId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;
  final double complianceRate;
  final DateTime generatedAtUtc;
  final List<String> snapshotIds;      // Provenance: which snapshots were aggregated
  final List<DateTime> operationalDates; // Provenance: which days were included
  final bool isComplete;               // False if gaps detected in period
  final List<DateTime> missingDates;   // Operational days without snapshots
}
```

> [!IMPORTANT]
> The report `id` is deterministic: `sha256(canonicalString)`. 
> Canonical format: `organizationId | contractScope | periodStartUtc | periodEndUtc`. 
> Dates are formatted as ISO-8601 strings. Same inputs always produce the same identifier.

> [!WARNING]
> If `isComplete` is false, the report includes a completeness warning. Aggregation still proceeds but auditors are alerted to missing operational days. Missing dates are computed from the expected operational day sequence (using snapshot `operationalDateUtc` fields).

### Aggregation Source

Reports are derived **exclusively from persisted daily snapshots** — never from raw execution states. This guarantees consistency: the report always reflects the same financial state as the snapshot that was closed.

> [!IMPORTANT]
> Aggregation is a pure read operation over immutable snapshots. No new data is created in the ledger or snapshot tables. Reports are ephemeral projection artifacts generated on demand. Snapshots are explicitly sorted by `operationalDateUtc` before aggregation — ordering is never assumed from repository queries.

## 4. Reporting Boundaries

| Dimension | Scope |
|---|---|
| **Per Organization** | All contracts for a tenant |
| **Per Contract** | Single contract within a tenant |
| **Per Billing Cycle** | Monthly (default), custom date range supported |
| **Daily** | Single operational day (existing snapshot) |

## 5. Export Formats

### CSV Export

Structured tabular export for integration with accounting systems:

```
Data Operacional, Receita Contratada, Receita Protegida, Receita em Risco, Receita Perdida, % Risco, % Perda
2026-03-01, 15000.00, 12000.00, 2000.00, 1000.00, 13.3, 6.7
2026-03-02, 14500.00, 13000.00, 1000.00, 500.00, 6.9, 3.4
```

### PDF Report

Formatted audit report with:
- Header: organization, contract, billing cycle
- Summary KPIs: total revenue, compliance rate, financial impact
- Daily breakdown table
- Signature block for contractual reconciliation

> [!NOTE]
> PDF generation uses the `pdf` package (`dart:io`-compatible). For Flutter web, CSV export is prioritized. PDF is generated server-side or on desktop platforms.

## 6. Consistency Guarantees

| Guarantee | Mechanism |
|---|---|
| Snapshot immutability | Daily snapshots are never modified after creation |
| Report determinism | Same date range + same snapshots = identical report |
| Provenance tracking | Report records `snapshotIds` it aggregated |
| Reprocessing visibility | Reprocessed snapshots carry `previousSnapshotId` chain |
| Ledger anchoring | Each snapshot carries `lastLedgerEntryId` boundary |

## 7. Application Layer

### `ReportingService`

```dart
class ReportingService {
  /// Generates a billing cycle report from persisted snapshots.
  /// Validates snapshot completeness and flags gaps.
  Future<BillingCycleReport> generateBillingCycleReport({
    required String organizationId,
    String? contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
  });

  /// Exports a billing cycle report as CSV bytes.
  /// Output is deterministic: same report → identical bytes.
  Future<List<int>> exportCsv(BillingCycleReport report);
}
```

### Aggregation Pipeline

```
User selects billing period in OCC
→ ReportingService queries snapshots for date range
→ Snapshots aggregated into BillingCycleReport
→ Report displayed in OCC
→ User exports as CSV or PDF
```

## 8. OCC Reporting Panel

A new **Relatórios** tab in the admin navigation:

- **Date range picker** — defaults to current month
- **Contract filter** — optional, defaults to all contracts
- **Summary KPIs** — total revenue, compliance rate, financial impact
- **Daily breakdown table** — one row per operational day
- **Export buttons** — "Exportar CSV" and "Exportar PDF"

> [!WARNING]
> The reporting panel is **strictly read-only**. No mutations to snapshots, ledger, or execution states are permitted from the reporting interface.

## 9. Tenant Isolation & Replay-Safe Aggregation

| Invariant | Enforcement |
|---|---|
| Tenant isolation | All queries filter by `organization_id`; export verifies requesting user belongs to same org |
| Replay safety | Reports aggregate only persisted, immutable snapshots — no runtime state |
| Idempotency | Same inputs produce identical reports (pure function over snapshots) |
| Domain sovereignty | `BillingCycleReport` is pure Dart, no Flutter dependencies |
| Provenance | Reports carry `snapshotIds` for full audit reconstruction |

## 10. Proposed Implementation Steps

### Domain Layer
#### [NEW] `lib/domain/sla_audit/billing_cycle_report.dart`

### Application Layer
#### [NEW] `lib/application/sla_audit/reporting_service.dart`
#### [NEW] `lib/application/sla_audit/csv_export_service.dart`
#### [NEW] `lib/application/sla_audit/pdf_export_service.dart`

### Provider Layer
#### [NEW] `lib/state/providers/reporting_providers.dart`

### Presentation Layer
#### [NEW] `lib/features/admin/presentation/screens/reporting_screen.dart`
#### [MODIFY] `lib/features/admin/presentation/screens/admin_main_screen.dart` (add Relatórios tab)

### Infrastructure
No new SQL tables required — reports are ephemeral projections over existing immutable snapshots.

## 11. Verification Plan

### Automated Tests
- Billing cycle aggregation from daily snapshots
- CSV export format correctness
- Empty period handling (no snapshots → zero-value report)
- Tenant isolation in snapshot queries
- Report determinism (same inputs → identical output)

### Manual Verification
- OCC Relatórios tab renders billing cycle data
- CSV download opens correctly in Excel/LibreOffice
- Date range filtering produces correct aggregation
