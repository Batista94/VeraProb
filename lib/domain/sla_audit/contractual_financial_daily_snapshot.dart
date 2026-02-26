import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../shared/money.dart';
import 'domain_exception.dart';

/// Immutable daily financial snapshot for contractual SLA obligations.
///
/// Represents the financial state of a contract (or all contracts) for a
/// specific operational day. Once created, cannot be modified — this ensures
/// auditability and prevents historical recalculation.
///
/// The [operationalDateUtc] is the normalized UTC date (00:00Z) derived
/// from the Brazil operational timezone (America/Sao_Paulo).
class ContractualFinancialDailySnapshot extends Equatable {
  final String id;
  final String? contractId;

  /// Operational day in normalized UTC (00:00Z).
  final DateTime operationalDateUtc;

  /// Timezone used to derive the operational day.
  final String operationalTimezone;

  /// Exact UTC instant when this snapshot was generated.
  final DateTime closedAtUtc;

  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;

  final double riskPercentage;
  final double lossPercentage;

  /// Causal linkage: The last ledger entry ID considered in this closure.
  /// Proves deterministically the exact boundary of events computed.
  final int? lastLedgerEntryId;

  /// Reprocessing chain: The ID of the snapshot this one replaces (if any).
  final String? previousSnapshotId;

  /// Reprocessing chain: Required justification if [previousSnapshotId] is set.
  final String? reprocessingReason;

  /// Auditing: The user who triggered the manual reprocessing (null for auto).
  final String? authorUserId;

  const ContractualFinancialDailySnapshot._({
    required this.id,
    required this.contractId,
    required this.operationalDateUtc,
    required this.operationalTimezone,
    required this.closedAtUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentage,
    required this.lossPercentage,
    required this.lastLedgerEntryId,
    this.previousSnapshotId,
    this.reprocessingReason,
    this.authorUserId,
  });

  /// Creates a new immutable daily financial snapshot.
  ///
  /// Percentages are calculated automatically from the monetary values.
  /// [operationalDateUtc] is normalized to midnight UTC.
  static ContractualFinancialDailySnapshot create({
    required String? contractId,
    required DateTime operationalDateUtc,
    required String operationalTimezone,
    required DateTime closedAtUtc,
    required Money totalContractedRevenue,
    required Money protectedRevenue,
    required Money revenueAtRisk,
    required Money lostRevenue,
    required int? lastLedgerEntryId,
    String? previousSnapshotId,
    String? reprocessingReason,
    String? authorUserId,
  }) {
    if (previousSnapshotId != null &&
        (reprocessingReason == null || reprocessingReason.trim().isEmpty)) {
      throw DomainException(
        'A reprocessing reason is required when providing a previousSnapshotId.',
      );
    }

    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    final totalCents = totalContractedRevenue.cents;
    final riskPercentage = totalCents > 0
        ? revenueAtRisk.cents / totalCents * 100
        : 0.0;
    final lossPercentage = totalCents > 0
        ? lostRevenue.cents / totalCents * 100
        : 0.0;

    return ContractualFinancialDailySnapshot._(
      id: const Uuid().v4(),
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: operationalTimezone,
      closedAtUtc: closedAtUtc,
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      riskPercentage: riskPercentage,
      lossPercentage: lossPercentage,
      lastLedgerEntryId: lastLedgerEntryId,
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    contractId,
    operationalDateUtc,
    operationalTimezone,
    closedAtUtc,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    riskPercentage,
    lossPercentage,
    lastLedgerEntryId,
    previousSnapshotId,
    reprocessingReason,
    authorUserId,
  ];
}
