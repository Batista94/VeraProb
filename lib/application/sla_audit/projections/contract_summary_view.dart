import 'package:equatable/equatable.dart';

import 'contract_status_view.dart';

/// Read model: individual [Contract] row for listing screens.
///
/// Flat projection from [Contract] aggregate + derived counters.
/// Immutable — no domain logic.
///
/// [slaHealthPercentage] is a display-only metric:
///   `(executedCount / totalSets) * 100`
/// where `totalSets = executed + noShow + evidenceGap + pending`.
/// Computed by [ContractQueryService], never in the UI.
class ContractSummaryView extends Equatable {
  final String id;
  final String name;
  final String contractorName;
  final ContractStatusView status;
  final DateTime validFromUtc;
  final DateTime validUntilUtc;
  final DateTime createdAtUtc;
  final DateTime? activatedAtUtc;

  /// Total number of [PlanDeclaration]s for this contract.
  final int planCount;

  /// Version of the most recently declared plan (0 if no plans yet).
  final int activePlanVersion;

  /// Number of SETs currently in [pending] status.
  final int totalSetsInProgress;

  /// SLA health in Basis Points: `(executed / total) * 10,000`.
  /// Returns 0 if no SETs exist.
  final int slaHealthBps;

  /// Maximum cumulative penalty cap for this contract (INV-2: cents).
  /// Required for Step 4 Relative Risk calculation.
  final int? financialCeilingCents;

  const ContractSummaryView({
    required this.id,
    required this.name,
    required this.contractorName,
    required this.status,
    required this.validFromUtc,
    required this.validUntilUtc,
    required this.createdAtUtc,
    this.activatedAtUtc,
    required this.planCount,
    required this.activePlanVersion,
    required this.totalSetsInProgress,
    required this.slaHealthBps,
    this.financialCeilingCents,
  });

  @override
  List<Object?> get props => [
    id,
    name,
    contractorName,
    status,
    validFromUtc,
    validUntilUtc,
    createdAtUtc,
    activatedAtUtc,
    planCount,
    activePlanVersion,
    totalSetsInProgress,
    slaHealthBps,
    financialCeilingCents,
  ];
}
