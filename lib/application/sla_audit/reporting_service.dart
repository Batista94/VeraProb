import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';

/// Service responsible for aggregating financial snapshots into billing cycle reports.
class ReportingService {
  final ContractualFinancialSnapshotRepository _snapshotRepo;

  ReportingService({
    required ContractualFinancialSnapshotRepository snapshotRepo,
  }) : _snapshotRepo = snapshotRepo;

  /// Generates a billing cycle report for a given period and organization.
  ///
  /// [contractId] can be null to aggregate all contracts for the organization.
  Future<BillingCycleReport> generateBillingCycleReport({
    required String organizationId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    String? contractId,
  }) async {
    // 1. Fetch snapshots in range
    final snapshots = await _snapshotRepo.findByDateRange(
      organizationId: organizationId,
      startUtc: periodStartUtc,
      endUtc: periodEndUtc,
      contractId: contractId,
    );

    // 2. Explicit chronological sorting (Council Refinement #2)
    snapshots.sort(
      (a, b) => a.operationalDateUtc.compareTo(b.operationalDateUtc),
    );

    // 3. Gap detection (Council Refinement #5)
    final missingDates = _detectMissingDates(
      periodStartUtc,
      periodEndUtc,
      snapshots.map((s) => s.operationalDateUtc).toSet(),
    );

    final isComplete = missingDates.isEmpty;

    // 4. Aggregation
    return BillingCycleReport.create(
      organizationId: organizationId,
      contractId: contractId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      snapshots: snapshots,
      isComplete: isComplete,
      missingDates: missingDates,
    );
  }

  List<DateTime> _detectMissingDates(
    DateTime start,
    DateTime end,
    Set<DateTime> presentDates,
  ) {
    final List<DateTime> missing = [];
    DateTime current = DateTime.utc(start.year, start.month, start.day);
    final normalizedEnd = DateTime.utc(end.year, end.month, end.day);

    while (current.isBefore(normalizedEnd) ||
        current.isAtSameMomentAs(normalizedEnd)) {
      if (!presentDates.contains(current)) {
        missing.add(current);
      }
      current = current.add(const Duration(days: 1));
    }
    return missing;
  }
}
