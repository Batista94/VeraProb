import 'package:veraprob/domain/sla_audit/shadow_mode_simulation.dart';

/// Read model for the Executive Dashboard screen.
///
/// Aggregates the five CFO KPIs, the Financial Protection Score (FPS),
/// revenue visualization data, and the most recent Shadow Mode simulation.
///
/// **FPS formula (Maverick spec — approved 2026-03-17):**
///   FPS = (40 × ComplianceScore + 25 × EvidenceScore
///           + 20 × RecoveryScore + 15 × TrendScore) / 100
///
/// **Evidence quality attribution (PO directive):**
/// When [evidenceScore] is low, the dashboard must display
/// [ShadowModeSimulation.evidenceQualityAttribution] to attribute the gap
/// to hardware quality — NOT to veraprob software.
class ExecutiveDashboardView {
  // ── Period ─────────────────────────────────────────────────────────────────
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final String organizationId;

  // ── KPI 1: Receita Blindada (cents — INV-19) ──────────────────────────────
  final int protectedRevenue;
  final int totalContractedRevenue;
  final int revenueAtRisk;
  final int lostRevenue;

  // ── KPI 2: Taxa de Recuperação de Penalidades ──────────────────────────────
  /// (lostRevenue.applied / lostRevenue.potential) × 100.
  /// Higher = more penalties successfully applied.
  final int penaltyRecoveryRate;

  // ── KPI 3: Dispute-to-Resolution Ratio ────────────────────────────────────
  /// (compensatingEntries.count / noShow.count) × 100. Lower = better.
  final int disputeToResolutionRatio;

  // ── KPI 4: Financial Protection Score (FPS) ────────────────────────────────
  /// Composite score [0–100].
  final int financialProtectionScore;

  // ── FPS sub-scores (for drill-down and attribution display) ────────────────
  /// executedCount / totalObligations × 100.
  final int complianceScore;

  /// canonical_facts.OK_count / total_facts × 100.
  /// Low value → display hardware attribution, NOT software failure.
  final int evidenceScore;

  /// lostRevenue.applied / lostRevenue.potential × 100.
  final int recoveryScore;

  /// Trend: month-over-month compliance improvement (sigmoid 0–100, 50 = neutral).
  final int trendScore;

  // ── KPI 5: SLA Compliance Trend ────────────────────────────────────────────
  /// Last 12 monthly compliance rates. Index 0 = oldest, last = most recent.
  final List<int> complianceTrend;

  // ── Obligation counts ──────────────────────────────────────────────────────
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  // ── FPS zone ───────────────────────────────────────────────────────────────
  FpsZone get fpsZone {
    if (financialProtectionScore >= 8000) {
      return FpsZone.protected;
    }
    if (financialProtectionScore >= 6000) {
      return FpsZone.moderate;
    }
    return FpsZone.highRisk;
  }

  // ── Shadow Mode ────────────────────────────────────────────────────────────
  final ShadowModeSimulation? latestShadowMode;

  // ── Recent packages ────────────────────────────────────────────────────────
  /// IDs of the 3 most recent sealed AuditPackages. For quick-access links.
  final List<String> recentSealedPackageIds;

  const ExecutiveDashboardView({
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.organizationId,
    required this.protectedRevenue,
    required this.totalContractedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.penaltyRecoveryRate,
    required this.disputeToResolutionRatio,
    required this.financialProtectionScore,
    required this.complianceScore,
    required this.evidenceScore,
    required this.recoveryScore,
    required this.trendScore,
    required this.complianceTrend,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.recentSealedPackageIds,
    this.latestShadowMode,
  });

  /// Builds an [ExecutiveDashboardView] from raw metrics.
  ///
  /// Computes FPS and all sub-scores from the provided inputs.
  ///
  /// [previousMonthComplianceRate]: compliance rate 3 months ago (for trend score).
  ///   Pass null if insufficient history — trend will default to neutral (50.0).
  /// Revenue protected by the shadow mode platform (cents). Null when no
  /// simulation has been run for this period.
  int? get latestShadowModeRevenueCents =>
      latestShadowMode?.revenueProtectedByPlatform.cents;

  factory ExecutiveDashboardView.compute({
    required String organizationId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required int protectedRevenue,
    required int totalContractedRevenue,
    required int revenueAtRisk,
    required int lostRevenue,
    required int totalObligations,
    required int executedCount,
    required int noShowCount,
    required int evidenceGapCount,
    required int okCanonicalFacts,
    required int totalCanonicalFacts,
    required int compensatingEntryCount,
    required List<int> complianceTrend,
    required List<String> recentSealedPackageIds,
    ShadowModeSimulation? latestShadowMode,
    int? previousMonthComplianceBps,
  }) {
    // Sub-scores
    final complianceScoreBps = totalObligations > 0
        ? (executedCount * 10000 ~/ totalObligations).clamp(0, 10000)
        : 10000;

    final evidenceScoreBps = totalCanonicalFacts > 0
        ? (okCanonicalFacts * 10000 ~/ totalCanonicalFacts).clamp(0, 10000)
        : 10000;

    // Recovery: ratio of penalties actually applied vs potential no-shows
    final potentialLoss = noShowCount + evidenceGapCount;
    final appliedPenalties = potentialLoss - compensatingEntryCount;
    final recoveryScoreBps = potentialLoss > 0
        ? (appliedPenalties * 10000 ~/ potentialLoss).clamp(0, 10000)
        : 10000;

    // Trend: sigmoid of compliance improvement over 3 months
    final currentCompliance = complianceScoreBps;
    final double trendDelta =
        previousMonthComplianceBps !=
            null // Bridge Conversion - Double Required
        ? (currentCompliance - previousMonthComplianceBps).toDouble() / 100.0
        : 0.0;
    final trendScoreBps = (ExecutiveDashboardView._sigmoid(trendDelta) * 100)
        .round()
        .clamp(0, 10000);

    // FPS composite
    final fpsBps =
        ((40 * complianceScoreBps +
                    25 * evidenceScoreBps +
                    20 * recoveryScoreBps +
                    15 * trendScoreBps) ~/
                100)
            .clamp(0, 10000);

    // Penalty recovery rate
    final penaltyRecoveryRateBps = potentialLoss > 0
        ? (appliedPenalties * 10000 ~/ potentialLoss).clamp(0, 10000)
        : 10000;

    // Dispute ratio
    final disputeRatioBps = noShowCount > 0
        ? (compensatingEntryCount * 10000 ~/ noShowCount).clamp(0, 10000)
        : 0;

    return ExecutiveDashboardView(
      organizationId: organizationId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      protectedRevenue: protectedRevenue,
      totalContractedRevenue: totalContractedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      penaltyRecoveryRate: penaltyRecoveryRateBps,
      disputeToResolutionRatio: disputeRatioBps,
      financialProtectionScore: fpsBps,
      complianceScore: complianceScoreBps,
      evidenceScore: evidenceScoreBps,
      recoveryScore: recoveryScoreBps,
      trendScore: trendScoreBps,
      complianceTrend: List.unmodifiable(complianceTrend),
      totalObligations: totalObligations,
      executedCount: executedCount,
      noShowCount: noShowCount,
      evidenceGapCount: evidenceGapCount,
      recentSealedPackageIds: List.unmodifiable(recentSealedPackageIds),
      latestShadowMode: latestShadowMode,
    );
  }

  static ExecutiveDashboardView empty(String organizationId) =>
      ExecutiveDashboardView(
        organizationId: organizationId,
        periodStartUtc: DateTime.utc(1970),
        periodEndUtc: DateTime.utc(1970),
        protectedRevenue: 0,
        totalContractedRevenue: 0,
        revenueAtRisk: 0,
        lostRevenue: 0,
        penaltyRecoveryRate: 0,
        disputeToResolutionRatio: 0,
        financialProtectionScore: 0,
        complianceScore: 0,
        evidenceScore: 0,
        recoveryScore: 0,
        trendScore: 5000,
        complianceTrend: const [],
        totalObligations: 0,
        executedCount: 0,
        noShowCount: 0,
        evidenceGapCount: 0,
        recentSealedPackageIds: const [],
      );

  /// Sigmoid maps a delta to [0, 100] with 50 as neutral.
  /// +10 delta → ~73  |  0 delta → 50  |  -10 delta → ~27.
  static double _sigmoid(double delta) {
    // Physical Metric - Double Required
    final s = 1.0 / (1.0 + _exp(-delta * 0.2));
    return (s * 100).clamp(0.0, 100.0);
  }

  static double _exp(double x) {
    // Physical Metric - Double Required
    return _dartExp(x);
  }

  // ignore: non_constant_identifier_names
  static double _dartExp(double x) {
    // Physical Metric - Double Required
    if (x > 20) {
      return double.maxFinite /
          2; // sigmoid → 1 // Physical Metric - Double Required
    }
    if (x < -20) {
      return 0.0000001; // sigmoid → 0
    }
    double result = 1.0; // Physical Metric - Double Required
    double term = 1.0; // Physical Metric - Double Required
    for (int n = 1; n <= 20; n++) {
      term *= x / n;
      result += term;
    }
    return result;
  }
}

/// The three FPS zones displayed on the Executive Dashboard radial gauge.
enum FpsZone {
  /// FPS 80–100. Dark green. "Proteção Forte"
  protected,

  /// FPS 60–79. Amber. "Proteção Adequada"
  moderate,

  /// FPS 0–59. Red. "Proteção Insuficiente"
  highRisk,
}
