import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/money.dart';
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
  final String organizationId;
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

  final int riskPercentageBps;
  final int lossPercentageBps;

  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  /// Causal linkage: The last ledger entry ID considered in this closure.
  /// Proves deterministically the exact boundary of events computed.
  final String? lastLedgerEntryId;

  /// Reprocessing chain: The ID of the snapshot this one replaces (if any).
  final String? previousSnapshotId;

  /// Reprocessing chain: Required justification if [previousSnapshotId] is set.
  final String? reprocessingReason;

  /// Auditing: The user who triggered the manual reprocessing (null for auto).
  final String? authorUserId;

  /// Engine version that produced this snapshot; resolved from
  /// [EnvironmentConfig.engineVersion] and injected via constructor (INV-13).
  /// Sealed at creation time for forensic replay auditability (INV-21).
  final String engineVersion;

  const ContractualFinancialDailySnapshot._({
    required this.id,
    required this.organizationId,
    required this.contractId,
    required this.operationalDateUtc,
    required this.operationalTimezone,
    required this.closedAtUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentageBps,
    required this.lossPercentageBps,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.lastLedgerEntryId,
    this.previousSnapshotId,
    this.reprocessingReason,
    this.authorUserId,
    required this.engineVersion,
  });

  /// Creates a new immutable daily financial snapshot.
  ///
  /// Percentages are calculated automatically from the monetary values.
  /// [operationalDateUtc] is normalized to midnight UTC.
  static ContractualFinancialDailySnapshot create({
    required String organizationId,
    required String? contractId,
    required DateTime operationalDateUtc,
    required String operationalTimezone,
    required DateTime closedAtUtc,
    required Money totalContractedRevenue,
    required Money protectedRevenue,
    required Money revenueAtRisk,
    required Money lostRevenue,
    required int totalObligations,
    required int executedCount,
    required int noShowCount,
    required int evidenceGapCount,
    required String? lastLedgerEntryId,
    required String engineVersion,
    String? previousSnapshotId,
    String? reprocessingReason,
    String? authorUserId,
  }) {
    if (engineVersion.trim().isEmpty) {
      throw const DomainException(
        'engineVersion must not be empty. Supply the value from EnvironmentConfig.engineVersion (INV-21).',
      );
    }

    if (previousSnapshotId != null &&
        (reprocessingReason == null || reprocessingReason.trim().isEmpty)) {
      throw const DomainException(
        'A reprocessing reason is required when providing a previousSnapshotId.',
      );
    }

    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    final totalCents = totalContractedRevenue.cents;
    final int riskBps = totalCents > 0
        ? (revenueAtRisk.cents * 10000 ~/ totalCents)
        : 0;
    final int lossBps = totalCents > 0
        ? (lostRevenue.cents * 10000 ~/ totalCents)
        : 0;

    return ContractualFinancialDailySnapshot._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: operationalTimezone,
      closedAtUtc: closedAtUtc,
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      riskPercentageBps: riskBps,
      lossPercentageBps: lossBps,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      lastLedgerEntryId: lastLedgerEntryId,
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
      engineVersion: engineVersion,
    );
  }

  /// Reconstitutes an existing snapshot from persistence without generating a new ID
  /// or recalculating percentages.
  factory ContractualFinancialDailySnapshot.reconstitute({
    required String id,
    required String organizationId,
    required String? contractId,
    required DateTime operationalDateUtc,
    required String operationalTimezone,
    required DateTime closedAtUtc,
    required Money totalContractedRevenue,
    required Money protectedRevenue,
    required Money revenueAtRisk,
    required Money lostRevenue,
    required int riskPercentageBps,
    required int lossPercentageBps,
    required int totalObligations,
    required int executedCount,
    required int noShowCount,
    required int evidenceGapCount,
    required String? lastLedgerEntryId,
    required String engineVersion,
    String? previousSnapshotId,
    String? reprocessingReason,
    String? authorUserId,
  }) {
    return ContractualFinancialDailySnapshot._(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      operationalDateUtc: operationalDateUtc,
      operationalTimezone: operationalTimezone,
      closedAtUtc: closedAtUtc,
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      riskPercentageBps: riskPercentageBps,
      lossPercentageBps: lossPercentageBps,
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      lastLedgerEntryId: lastLedgerEntryId,
      previousSnapshotId: previousSnapshotId,
      reprocessingReason: reprocessingReason,
      authorUserId: authorUserId,
      engineVersion: engineVersion,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    contractId,
    operationalDateUtc,
    operationalTimezone,
    closedAtUtc,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    riskPercentageBps,
    lossPercentageBps,
    totalObligations,
    executedCount,
    noShowCount,
    evidenceGapCount,
    lastLedgerEntryId,
    previousSnapshotId,
    reprocessingReason,
    authorUserId,
    engineVersion,
  ];
}
