import 'package:veraprob/domain/shared/brazil_time.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';

/// Generates immutable daily financial snapshots from execution states.
///
/// Snapshots are derived by:
/// 1. Filtering execution states whose `windowStartUtc` falls on the
///    given operational day (converted to BRT timezone)
/// 2. Accumulating monetary values using [Money] (no floating-point intermediaries)
/// 3. Persisting the resulting snapshot with engine version sealing
///
/// The generation is idempotent: if a snapshot already exists for the
/// given day, the method returns immediately.
class ContractualFinancialSnapshotGenerator {
  final ContractualExecutionStateRepository _executionRepo;
  final ContractualFinancialSnapshotRepository _snapshotRepo;
  final SlaAuditLedgerRepository _ledgerRepo;
  final IDateTimeProvider _clock;

  /// The engine version sealed into every snapshot produced by this generator.
  /// Injected by the composition root (INV-13: application layer must not
  /// import infrastructure/config/environment.dart directly).
  final String _engineVersion;

  ContractualFinancialSnapshotGenerator({
    required ContractualExecutionStateRepository executionRepo,
    required ContractualFinancialSnapshotRepository snapshotRepo,
    required SlaAuditLedgerRepository ledgerRepo,
    required IDateTimeProvider clock,
    required String engineVersion,
  }) : _executionRepo = executionRepo,
       _snapshotRepo = snapshotRepo,
       _ledgerRepo = ledgerRepo,
       _clock = clock,
       _engineVersion = engineVersion;

  /// Generates a daily financial snapshot for the given operational date.
  ///
  /// [operationalDateUtc] must be a normalized UTC date (00:00Z).
  /// If a snapshot already exists for this date, this is a no-op (idempotent).
  Future<void> generateDailySnapshot(
    String organizationId,
    DateTime operationalDateUtc, {
    String? contractId,
    DateTime? closedAtUtc,
  }) async {
    final normalizedDate = _normalizeDate(operationalDateUtc);

    // Idempotency check: avoid creating duplicate active snapshots
    final exists = await _snapshotRepo.existsForDate(
      organizationId,
      normalizedDate,
      contractId: contractId,
    );
    if (exists) return;

    final dayStates = await _collectExecutionMetrics(
      organizationId,
      normalizedDate,
      contractId: contractId,
    );

    // Guard: zero states in a contract scope means no obligations (INV-6)
    if (contractId != null && dayStates.isEmpty) return;

    final metrics = _calculateFinancialTotals(dayStates);

    await _persistSnapshot(
      organizationId: organizationId,
      normalizedDate: normalizedDate,
      metrics: metrics,
      contractId: contractId,
      closedAtUtc: closedAtUtc,
    );
  }

  /// Manually reprocesses a financial snapshot for a given operational date.
  /// Generates a new snapshot that explicitly supersedes the active one.
  Future<void> reprocessDailySnapshot(
    String organizationId,
    DateTime operationalDateUtc, {
    required String previousSnapshotId,
    required String reprocessingReason,
    required String authorUserId,
    String? contractId,
    DateTime? closedAtUtc,
  }) async {
    final normalizedDate = _normalizeDate(operationalDateUtc);

    // Guard: Prevent duplicate reprocessing chains (INV-33)
    await _assertNoExistingSupersession(
      organizationId,
      previousSnapshotId,
      contractId: contractId,
    );

    final dayStates = await _collectExecutionMetrics(
      organizationId,
      normalizedDate,
      contractId: contractId,
    );

    final metrics = _calculateFinancialTotals(dayStates);

    await _persistSnapshot(
      organizationId: organizationId,
      normalizedDate: normalizedDate,
      metrics: metrics,
      contractId: contractId,
      closedAtUtc: closedAtUtc,
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
    );
  }

  // ── Private Helper Methods (SRP Decomposition) ──────────────────────────────

  DateTime _normalizeDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  Future<List<ContractualExecutionState>> _collectExecutionMetrics(
    String organizationId,
    DateTime normalizedDate, {
    String? contractId,
  }) async {
    final allStates = contractId != null
        ? await _executionRepo.findByContract(
            contractId,
            organizationId: organizationId,
          )
        : await _executionRepo.findAll(organizationId: organizationId);

    return allStates.where((s) {
      return BrazilTime.isSameOperationalDay(s.windowStartUtc, normalizedDate);
    }).toList();
  }

  _DailyFinancialMetrics _calculateFinancialTotals(
    List<ContractualExecutionState> states,
  ) {
    Money totalContractedRevenue = const Money(0);
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    int totalObligations = states.length;
    int executedCount = 0;
    int noShowCount = 0;
    int evidenceGapCount = 0;

    for (final s in states) {
      final value = s.contractualValue;
      totalContractedRevenue = totalContractedRevenue + value;

      switch (s.status) {
        case ExecutionStatus.planned:
        case ExecutionStatus.inTransit:
          revenueAtRisk = revenueAtRisk + value;
          break;
        case ExecutionStatus.completed:
          protectedRevenue = protectedRevenue + value;
          executedCount++;
          break;
        case ExecutionStatus.failed:
          lostRevenue = lostRevenue + value.multiplyByBps(s.noShowPenaltyBps);
          noShowCount++;
          break;
        case ExecutionStatus.completedWithGaps:
          revenueAtRisk = revenueAtRisk + value;
          evidenceGapCount++;
          break;
        case ExecutionStatus.inhibited:
          // Penalty suppressed — counts as protected revenue for reconciliation
          protectedRevenue = protectedRevenue + value;
          executedCount++;
          break;
      }
    }

    return _DailyFinancialMetrics(
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
    );
  }

  Future<void> _assertNoExistingSupersession(
    String organizationId,
    String previousSnapshotId, {
    String? contractId,
  }) async {
    // Queries ALL rows (active and superseded) for any snapshot that lists
    // previousSnapshotId as its predecessor. findAll would only see heads,
    // missing mid-chain entries and allowing illegal lineage branches (INV-33).
    final alreadySuperseded = await _snapshotRepo.existsSuperseding(
      organizationId,
      previousSnapshotId,
    );

    if (alreadySuperseded) {
      throw DomainException(
        'Snapshot $previousSnapshotId has already been superseded. '
        'Branching blocked to preserve forensic lineage integrity (INV-33).',
      );
    }
  }

  Future<void> _persistSnapshot({
    required String organizationId,
    required DateTime normalizedDate,
    required _DailyFinancialMetrics metrics,
    String? contractId,
    DateTime? closedAtUtc,
    String? previousSnapshotId,
    String? reprocessingReason,
    String? authorUserId,
  }) async {
    final snapshot = ContractualFinancialDailySnapshot.create(
      organizationId: organizationId,
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: BrazilTime.operationalTimezone,
      closedAtUtc: closedAtUtc ?? _clock.nowUtc(),
      totalContractedRevenue: metrics.totalContractedRevenue,
      protectedRevenue: metrics.protectedRevenue,
      revenueAtRisk: metrics.revenueAtRisk,
      lostRevenue: metrics.lostRevenue,
      totalObligations: metrics.totalObligations,
      executedCount: metrics.executedCount,
      noShowCount: metrics.noShowCount,
      evidenceGapCount: metrics.evidenceGapCount,
      lastLedgerEntryId: await _ledgerRepo.getLastEntryId(
        organizationId: organizationId,
        contractId: contractId,
      ),
      engineVersion: _engineVersion,
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
    );

    await _snapshotRepo.save(snapshot);
  }
}

/// Immutable carrier for daily financial metrics (INV-4).
class _DailyFinancialMetrics {
  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;

  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  const _DailyFinancialMetrics({
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
  });
}
