import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

import '../shared/money.dart';
import 'contractual_financial_daily_snapshot.dart';

/// Ephemeral read model representing a financial aggregation for a billing cycle.
///
/// Generated on-demand from immutable [ContractualFinancialDailySnapshot] records.
/// The [id] is deterministic, ensuring same inputs produce same report identity.
class BillingCycleReport extends Equatable {
  final String id;
  final String organizationId;
  final String? contractId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;

  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;

  /// The daily snapshots aggregated into this report.
  final List<ContractualFinancialDailySnapshot> snapshots;

  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  final double complianceRate;
  final DateTime generatedAtUtc;

  /// Provenance: identifiers of the daily snapshots aggregated into this report.
  final List<String> snapshotIds;

  /// Provenance: operational dates included in this report.
  final List<DateTime> operationalDates;

  /// Audit flag: true if the report covers all expected days in the period.
  final bool isComplete;

  /// Audit detail: operational days in the period that were missing snapshots.
  final List<DateTime> missingDates;

  const BillingCycleReport({
    required this.id,
    required this.organizationId,
    this.contractId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.snapshots,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.complianceRate,
    required this.generatedAtUtc,
    required this.snapshotIds,
    required this.operationalDates,
    required this.isComplete,
    required this.missingDates,
  });

  /// Factory to create a report with a deterministic ID.
  static BillingCycleReport create({
    required String organizationId,
    String? contractId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required List<ContractualFinancialDailySnapshot> snapshots,
    required bool isComplete,
    required List<DateTime> missingDates,
    DateTime? generatedAtUtc,
  }) {
    final contractScope = contractId ?? 'ALL';
    final startStr = periodStartUtc.toIso8601String();
    final endStr = periodEndUtc.toIso8601String();

    // Aggregation Logic
    Money totalContracted = const Money(0);
    Money protected = const Money(0);
    Money atRisk = const Money(0);
    Money lost = const Money(0);

    int totalOb = 0;
    int exec = 0;
    int noShow = 0;
    int gap = 0;

    for (final s in snapshots) {
      totalContracted += s.totalContractedRevenue;
      protected += s.protectedRevenue;
      atRisk += s.revenueAtRisk;
      lost += s.lostRevenue;
      totalOb += s.totalObligations;
      exec += s.executedCount;
      noShow += s.noShowCount;
      gap += s.evidenceGapCount;
    }

    final double compliance = totalOb > 0 ? (exec / totalOb) * 100 : 100.0;

    // Canonical ID generation
    final canonicalString = '$organizationId|$contractScope|$startStr|$endStr';
    final bytes = utf8.encode(canonicalString);
    final hash = sha256.convert(bytes).toString();

    return BillingCycleReport(
      id: hash,
      organizationId: organizationId,
      contractId: contractId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      totalContractedRevenue: totalContracted,
      protectedRevenue: protected,
      revenueAtRisk: atRisk,
      lostRevenue: lost,
      snapshots: List.unmodifiable(snapshots),
      totalObligations: totalOb,
      executedCount: exec,
      noShowCount: noShow,
      evidenceGapCount: gap,
      complianceRate: compliance,
      generatedAtUtc: generatedAtUtc ?? DateTime.now().toUtc(),
      snapshotIds: snapshots.map((s) => s.id).toList(),
      operationalDates: snapshots.map((s) => s.operationalDateUtc).toList(),
      isComplete: isComplete,
      missingDates: List.unmodifiable(missingDates),
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    contractId,
    periodStartUtc,
    periodEndUtc,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    totalObligations,
    executedCount,
    noShowCount,
    evidenceGapCount,
    complianceRate,
    snapshots,
    generatedAtUtc,
    snapshotIds,
    operationalDates,
    isComplete,
    missingDates,
  ];
}
