import '../../../core/time/brazil_time.dart';
import '../../../domain/shared/money.dart';
import '../../../domain/sla_audit/contractual_execution_state_repository.dart';
import '../../../domain/sla_audit/contractual_financial_daily_snapshot.dart';
import '../../../domain/sla_audit/contractual_financial_snapshot_repository.dart';
import '../../../domain/sla_audit/execution_status.dart';
import '../../../domain/sla_audit/sla_audit_ledger_repository.dart';

/// Generates immutable daily financial snapshots from execution states.
///
/// Snapshots are derived by:
/// 1. Filtering execution states whose `windowStartUtc` falls on the
///    given operational day (converted to BRT timezone)
/// 2. Accumulating monetary values using [Money] (no double intermediaries)
/// 3. Persisting the resulting snapshot
///
/// The generation is idempotent: if a snapshot already exists for the
/// given day, the method returns immediately.
class ContractualFinancialSnapshotGenerator {
  final ContractualExecutionStateRepository _executionRepo;
  final ContractualFinancialSnapshotRepository _snapshotRepo;
  final SlaAuditLedgerRepository _ledgerRepo;

  ContractualFinancialSnapshotGenerator({
    required ContractualExecutionStateRepository executionRepo,
    required ContractualFinancialSnapshotRepository snapshotRepo,
    required SlaAuditLedgerRepository ledgerRepo,
  }) : _executionRepo = executionRepo,
       _snapshotRepo = snapshotRepo,
       _ledgerRepo = ledgerRepo;

  /// Generates a daily financial snapshot for the given operational date.
  ///
  /// [operationalDateUtc] must be a normalized UTC date (00:00Z).
  /// If a snapshot already exists for this date, this is a no-op (idempotent).
  Future<void> generateDailySnapshot(
    DateTime operationalDateUtc, {
    String? contractId,
  }) async {
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    // Idempotency check
    final exists = await _snapshotRepo.existsForDate(
      normalizedDate,
      contractId: contractId,
    );
    if (exists) return;

    // Fetch execution states
    final allStates = contractId != null
        ? await _executionRepo.findByContract(contractId)
        : await _executionRepo.findAll();

    // Filter states belonging to this operational day (BRT timezone)
    final dayStates = allStates.where((s) {
      return BrazilTime.isSameOperationalDay(s.windowStartUtc, normalizedDate);
    }).toList();

    // Accumulate using Money exclusively
    Money totalContractedRevenue = const Money(0);
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    for (final s in dayStates) {
      final value = Money.fromDouble(s.contractualValue);
      totalContractedRevenue = totalContractedRevenue + value;

      switch (s.status) {
        case ExecutionStatus.pending:
          revenueAtRisk = revenueAtRisk + value;
          break;
        case ExecutionStatus.executed:
          protectedRevenue = protectedRevenue + value;
          break;
        case ExecutionStatus.noShow:
          lostRevenue = lostRevenue + (value * s.noShowPenaltyMultiplier);
          break;
        case ExecutionStatus.evidenceGap:
          revenueAtRisk = revenueAtRisk + value;
          break;
      }
    }

    // Create and persist snapshot
    final snapshot = ContractualFinancialDailySnapshot.create(
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: BrazilTime.operationalTimezone,
      closedAtUtc: DateTime.now().toUtc(),
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      lastLedgerEntryId: await _ledgerRepo.getLastEntryId(),
    );

    await _snapshotRepo.save(snapshot);
  }

  /// Manually reprocesses a financial snapshot for a given operational date.
  /// Generates a new snapshot that explicitly supersedes the active one.
  Future<void> reprocessDailySnapshot(
    DateTime operationalDateUtc, {
    required String previousSnapshotId,
    required String reprocessingReason,
    required String authorUserId,
    String? contractId,
  }) async {
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    final allStates = contractId != null
        ? await _executionRepo.findByContract(contractId)
        : await _executionRepo.findAll();

    final dayStates = allStates.where((s) {
      return BrazilTime.isSameOperationalDay(s.windowStartUtc, normalizedDate);
    }).toList();

    Money totalContractedRevenue = const Money(0);
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    for (final s in dayStates) {
      final value = Money.fromDouble(s.contractualValue);
      totalContractedRevenue = totalContractedRevenue + value;

      switch (s.status) {
        case ExecutionStatus.pending:
          revenueAtRisk = revenueAtRisk + value;
          break;
        case ExecutionStatus.executed:
          protectedRevenue = protectedRevenue + value;
          break;
        case ExecutionStatus.noShow:
          lostRevenue = lostRevenue + (value * s.noShowPenaltyMultiplier);
          break;
        case ExecutionStatus.evidenceGap:
          revenueAtRisk = revenueAtRisk + value;
          break;
      }
    }

    final snapshot = ContractualFinancialDailySnapshot.create(
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: BrazilTime.operationalTimezone,
      closedAtUtc: DateTime.now().toUtc(),
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      lastLedgerEntryId: await _ledgerRepo.getLastEntryId(),
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
    );

    await _snapshotRepo.save(snapshot);
  }
}
