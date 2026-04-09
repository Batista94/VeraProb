import 'package:veraprob/core/time/brazil_time.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';

/// Generates immutable daily financial snapshots from execution states.
///
/// Snapshots are derived by:
/// 1. Filtering execution states whose `windowStartUtc` falls on the
///    given operational day (converted to BRT timezone)
/// 2. Accumulating monetary values using [Money] (no floating-point intermediaries)
/// 3. Persisting the resulting snapshot
///
/// The generation is idempotent: if a snapshot already exists for the
/// given day, the method returns immediately.
class ContractualFinancialSnapshotGenerator {
  final ContractualExecutionStateRepository _executionRepo;
  final ContractualFinancialSnapshotRepository _snapshotRepo;
  final SlaAuditLedgerRepository _ledgerRepo;
  final IDateTimeProvider _clock;

  ContractualFinancialSnapshotGenerator({
    required ContractualExecutionStateRepository executionRepo,
    required ContractualFinancialSnapshotRepository snapshotRepo,
    required SlaAuditLedgerRepository ledgerRepo,
    required IDateTimeProvider clock,
  }) : _executionRepo = executionRepo,
       _snapshotRepo = snapshotRepo,
       _ledgerRepo = ledgerRepo,
       _clock = clock;

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
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    // Idempotency check
    final exists = await _snapshotRepo.existsForDate(
      organizationId,
      normalizedDate,
      contractId: contractId,
    );
    if (exists) return;

    // Fetch execution states
    final allStates = contractId != null
        ? await _executionRepo.findByContract(
            contractId,
            organizationId: organizationId,
          )
        : await _executionRepo.findAll(organizationId: organizationId);

    // Filter states belonging to this operational day (BRT timezone)
    final dayStates = allStates.where((s) {
      return BrazilTime.isSameOperationalDay(s.windowStartUtc, normalizedDate);
    }).toList();

    // Guard: when a contractId is scoped, zero states means either the contract
    // belongs to another org or has no obligations that day — do not persist an
    // empty cross-tenant snapshot (INV-6). Org-level snapshots (no contractId)
    // may legitimately be zero and are still persisted.
    if (contractId != null && dayStates.isEmpty) return;

    // Accumulate metrics
    Money totalContractedRevenue = const Money(0);
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    int totalObligations = dayStates.length;
    int executedCount = 0;
    int noShowCount = 0;
    int evidenceGapCount = 0;

    for (final s in dayStates) {
      final value = s.contractualValue;
      totalContractedRevenue = totalContractedRevenue + value;

      switch (s.status) {
        case ExecutionStatus.pending:
          revenueAtRisk = revenueAtRisk + value;
          break;
        case ExecutionStatus.executed:
          protectedRevenue = protectedRevenue + value;
          executedCount++;
          break;
        case ExecutionStatus.noShow:
          lostRevenue = lostRevenue + value.multiplyByBps(s.noShowPenaltyBps);
          noShowCount++;
          break;
        case ExecutionStatus.evidenceGap:
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

    // Create and persist snapshot
    final snapshot = ContractualFinancialDailySnapshot.create(
      organizationId: organizationId,
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: BrazilTime.operationalTimezone,
      closedAtUtc: closedAtUtc ?? _clock.now(),
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      lastLedgerEntryId: await _ledgerRepo.getLastEntryId(
        organizationId: organizationId,
        contractId: contractId,
      ),
    );

    await _snapshotRepo.save(snapshot);
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
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    final allStates = contractId != null
        ? await _executionRepo.findByContract(
            contractId,
            organizationId: organizationId,
          )
        : await _executionRepo.findAll(organizationId: organizationId);

    final dayStates = allStates.where((s) {
      return BrazilTime.isSameOperationalDay(s.windowStartUtc, normalizedDate);
    }).toList();

    Money totalContractedRevenue = const Money(0);
    Money protectedRevenue = const Money(0);
    Money revenueAtRisk = const Money(0);
    Money lostRevenue = const Money(0);

    int totalObligations = dayStates.length;
    int executedCount = 0;
    int noShowCount = 0;
    int evidenceGapCount = 0;

    for (final s in dayStates) {
      final value = s.contractualValue;
      totalContractedRevenue = totalContractedRevenue + value;

      switch (s.status) {
        case ExecutionStatus.pending:
          revenueAtRisk = revenueAtRisk + value;
          break;
        case ExecutionStatus.executed:
          protectedRevenue = protectedRevenue + value;
          executedCount++;
          break;
        case ExecutionStatus.noShow:
          lostRevenue = lostRevenue + value.multiplyByBps(s.noShowPenaltyBps);
          noShowCount++;
          break;
        case ExecutionStatus.evidenceGap:
          revenueAtRisk = revenueAtRisk + value;
          evidenceGapCount++;
          break;
        case ExecutionStatus.inhibited:
          protectedRevenue = protectedRevenue + value;
          executedCount++;
          break;
      }
    }

    final snapshot = ContractualFinancialDailySnapshot.create(
      organizationId: organizationId,
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: BrazilTime.operationalTimezone,
      closedAtUtc: closedAtUtc ?? _clock.now(),
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      lastLedgerEntryId: await _ledgerRepo.getLastEntryId(
        organizationId: organizationId,
        contractId: contractId,
      ),
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
    );

    await _snapshotRepo.save(snapshot);
  }
}
