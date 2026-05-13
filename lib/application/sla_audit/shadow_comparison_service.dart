import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict_repository.dart';

/// Value object: divergence report for a time window.
///
/// Captures all divergence metrics between the EvaluationEngine's shadow
/// verdicts and human auditor decisions recorded in the sanction queue.
///
/// [matchRate] is computed only over [totalCompared] entries (those with a
/// human decision). Entries still [ShadowDivergenceType.pendingManual] are
/// excluded from the rate to avoid artificially inflating it.
///
/// [criticalDivergenceDetected] is true when [totalCompared] > 0 and
/// [matchRate] falls below the configured threshold (default 80%).
/// When raised, a SEVERE log is emitted by [ShadowComparisonService] and
/// this flag allows the UI/alerting layer to surface the signal immediately.
class ShadowComparisonReport extends Equatable {
  final String organizationId;
  final DateTime fromUtc;
  final DateTime toUtc;

  /// All shadow_verdicts in the time window (compared + pending).
  final int totalEvaluated;

  /// Subset with a human decision — the denominator for [matchRate].
  final int totalCompared;

  /// Percentage of compared verdicts where engine == human (0.0–100.0).
  /// 0.0 when [totalCompared] == 0 (no human decisions yet in window).
  final double matchRate; // Physical Metric - Double Required

  /// Engine applied penalty; human rejected it.
  final int falsePositiveCount;

  /// Engine cleared obligation; human applied penalty.
  final int falseNegativeCount;

  /// Awaiting a human decision — excluded from [matchRate].
  final int pendingManualCount;

  /// FP + FN entries for SuperAdmin drill-down.
  final List<ShadowVerdict> divergentEntries;

  /// True when [totalCompared] > 0 and [matchRate] < threshold.
  /// A SEVERE log was emitted when this is true.
  final bool criticalDivergenceDetected;

  final DateTime generatedAtUtc;

  const ShadowComparisonReport({
    required this.organizationId,
    required this.fromUtc,
    required this.toUtc,
    required this.totalEvaluated,
    required this.totalCompared,
    required this.matchRate,
    required this.falsePositiveCount,
    required this.falseNegativeCount,
    required this.pendingManualCount,
    required this.divergentEntries,
    required this.criticalDivergenceDetected,
    required this.generatedAtUtc,
  });

  @override
  List<Object?> get props => [
    organizationId,
    fromUtc,
    toUtc,
    totalEvaluated,
    totalCompared,
    matchRate,
    falsePositiveCount,
    falseNegativeCount,
    pendingManualCount,
    criticalDivergenceDetected,
    generatedAtUtc,
  ];
}

/// Orchestrates divergence analysis between shadow engine verdicts and
/// human-reviewed decisions from the sanction queue.
///
/// **Critical Divergence alert:**
/// If [matchRate] falls below [criticalDivergenceThreshold] (default 80.0%)
/// for any window with at least one compared entry, a SEVERE-level log is
/// emitted via `dart:developer` and [ShadowComparisonReport.criticalDivergenceDetected]
/// is set to true. This is the primary signal for immediate SuperAdmin review
/// of a potential logic failure in the EvaluationEngine's inhibition or
/// verdict classification paths.
class ShadowComparisonService {
  final ShadowVerdictRepository _shadowRepo;
  final IDateTimeProvider _dateTimeProvider;

  /// Threshold below which a divergence is classified as critical.
  /// Configurable for testing; production default is 80.0%.
  final double criticalDivergenceThreshold; // Physical Metric - Double Required

  ShadowComparisonService({
    required ShadowVerdictRepository shadowRepo,
    required IDateTimeProvider dateTimeProvider,
    this.criticalDivergenceThreshold = 80.0,
  }) : _shadowRepo = shadowRepo,
       _dateTimeProvider = dateTimeProvider;

  /// Syncs manual decisions from the sanction queue, then computes
  /// divergence metrics for the given UTC time window.
  ///
  /// Throws [ArgumentError] if [fromUtc] or [toUtc] are not UTC, or if
  /// [fromUtc] is after [toUtc].
  Future<ShadowComparisonReport> generateReport({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    if (!fromUtc.isUtc || !toUtc.isUtc) {
      throw ArgumentError('fromUtc and toUtc must be UTC (INV-9)');
    }
    if (fromUtc.isAfter(toUtc)) {
      throw ArgumentError('fromUtc must not be after toUtc');
    }

    // 1. Pull human decisions from sanction_review_queue into shadow_verdicts.
    await _shadowRepo.syncManualVerdicts(organizationId: organizationId);

    // 2. Fetch all shadow verdicts in the window.
    final all = await _shadowRepo.findByOrganization(
      organizationId: organizationId,
      fromUtc: fromUtc,
      toUtc: toUtc,
    );

    // 3. Partition by decision state.
    final compared = all
        .where((v) => v.divergenceType != ShadowDivergenceType.pendingManual)
        .toList();
    final matchCount = compared
        .where((v) => v.divergenceType == ShadowDivergenceType.match)
        .length;
    final fpCount = compared
        .where((v) => v.divergenceType == ShadowDivergenceType.falsePositive)
        .length;
    final fnCount = compared
        .where((v) => v.divergenceType == ShadowDivergenceType.falseNegative)
        .length;
    final pendingCount = all
        .where((v) => v.divergenceType == ShadowDivergenceType.pendingManual)
        .length;
    final divergentEntries = compared
        .where((v) => v.divergenceType != ShadowDivergenceType.match)
        .toList();

    // matchRate denominator = totalCompared only (pending excluded).
    final matchRate = compared.isEmpty
        ? 0.0
        : (matchCount / compared.length) * 100.0;

    // 4. Critical divergence check — only fires when there is real comparison data.
    final isCritical =
        compared.isNotEmpty && matchRate < criticalDivergenceThreshold;

    if (isCritical) {
      developer.log(
        '[CRITICAL DIVERGENCE] '
        'org=$organizationId '
        'matchRate=${matchRate.toStringAsFixed(1)}% '
        'threshold=${criticalDivergenceThreshold.toStringAsFixed(1)}% '
        'FP=$fpCount FN=$fnCount '
        'divergentEntries=${divergentEntries.length} '
        'window=${fromUtc.toIso8601String()}â†’${toUtc.toIso8601String()} '
        '— Requires immediate SuperAdmin review of EvaluationEngine '
        'verdict/inhibition logic.',
        name: 'ShadowComparisonService',
        level: 1000, // SEVERE — maps to ERROR in the Dart log hierarchy
      );
    }

    return ShadowComparisonReport(
      organizationId: organizationId,
      fromUtc: fromUtc,
      toUtc: toUtc,
      totalEvaluated: all.length,
      totalCompared: compared.length,
      matchRate: matchRate,
      falsePositiveCount: fpCount,
      falseNegativeCount: fnCount,
      pendingManualCount: pendingCount,
      divergentEntries: divergentEntries,
      criticalDivergenceDetected: isCritical,
      generatedAtUtc: _dateTimeProvider.nowUtc(),
    );
  }
}
