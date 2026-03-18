import '../../../domain/shared/money.dart';
import '../../../domain/sla_audit/shadow_mode_simulation.dart';

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
/// to hardware quality — NOT to PactaFlow software.
class ExecutiveDashboardView {
  // ── Period ─────────────────────────────────────────────────────────────────
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final String organizationId;

  // ── KPI 1: Receita Blindada ────────────────────────────────────────────────
  final Money protectedRevenue;
  final Money totalContractedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;

  // ── KPI 2: Taxa de Recuperação de Penalidades ──────────────────────────────
  /// (lostRevenue.applied / lostRevenue.potential) × 100.
  /// Higher = more penalties successfully applied.
  final double penaltyRecoveryRate;

  // ── KPI 3: Dispute-to-Resolution Ratio ────────────────────────────────────
  /// (compensatingEntries.count / noShow.count) × 100. Lower = better.
  final double disputeToResolutionRatio;

  // ── KPI 4: Financial Protection Score (FPS) ────────────────────────────────
  /// Composite score [0–100].
  final double financialProtectionScore;

  // ── FPS sub-scores (for drill-down and attribution display) ────────────────
  /// executedCount / totalObligations × 100.
  final double complianceScore;

  /// canonical_facts.OK_count / total_facts × 100.
  /// Low value → display hardware attribution, NOT software failure.
  final double evidenceScore;

  /// lostRevenue.applied / lostRevenue.potential × 100.
  final double recoveryScore;

  /// Trend: month-over-month compliance improvement (sigmoid 0–100, 50 = neutral).
  final double trendScore;

  // ── KPI 5: SLA Compliance Trend ────────────────────────────────────────────
  /// Last 12 monthly compliance rates. Index 0 = oldest, last = most recent.
  final List<double> complianceTrend;

  // ── Obligation counts ──────────────────────────────────────────────────────
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  // ── FPS zone ───────────────────────────────────────────────────────────────
  FpsZone get fpsZone {
    if (financialProtectionScore >= 80) return FpsZone.protected;
    if (financialProtectionScore >= 60) return FpsZone.moderate;
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
  factory ExecutiveDashboardView.compute({
    required String organizationId,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required Money protectedRevenue,
    required Money totalContractedRevenue,
    required Money revenueAtRisk,
    required Money lostRevenue,
    required int totalObligations,
    required int executedCount,
    required int noShowCount,
    required int evidenceGapCount,
    required int okCanonicalFacts,
    required int totalCanonicalFacts,
    required int compensatingEntryCount,
    required List<double> complianceTrend,
    required List<String> recentSealedPackageIds,
    ShadowModeSimulation? latestShadowMode,
    double? previousMonthComplianceRate,
  }) {
    // Sub-scores
    final complianceScore = totalObligations > 0
        ? (executedCount / totalObligations * 100).clamp(0.0, 100.0)
        : 100.0;

    final evidenceScore = totalCanonicalFacts > 0
        ? (okCanonicalFacts / totalCanonicalFacts * 100).clamp(0.0, 100.0)
        : 100.0;

    // Recovery: ratio of penalties actually applied vs potential no-shows
    final potentialLoss = noShowCount + evidenceGapCount;
    final appliedPenalties = potentialLoss - compensatingEntryCount;
    final recoveryScore = potentialLoss > 0
        ? (appliedPenalties / potentialLoss * 100).clamp(0.0, 100.0)
        : 100.0;

    // Trend: sigmoid of compliance improvement over 3 months
    final currentCompliance = complianceScore;
    final trendDelta = previousMonthComplianceRate != null
        ? currentCompliance - previousMonthComplianceRate
        : 0.0;
    final trendScore = _sigmoid(trendDelta);

    // FPS composite
    final fps =
        ((40 * complianceScore +
                    25 * evidenceScore +
                    20 * recoveryScore +
                    15 * trendScore) /
                100)
            .clamp(0.0, 100.0);

    // Penalty recovery rate
    final penaltyRecoveryRate = potentialLoss > 0
        ? (appliedPenalties / potentialLoss * 100).clamp(0.0, 100.0)
        : 100.0;

    // Dispute ratio
    final disputeRatio = noShowCount > 0
        ? (compensatingEntryCount / noShowCount * 100).clamp(0.0, 100.0)
        : 0.0;

    return ExecutiveDashboardView(
      organizationId: organizationId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      protectedRevenue: protectedRevenue,
      totalContractedRevenue: totalContractedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      penaltyRecoveryRate: penaltyRecoveryRate,
      disputeToResolutionRatio: disputeRatio,
      financialProtectionScore: fps,
      complianceScore: complianceScore,
      evidenceScore: evidenceScore,
      recoveryScore: recoveryScore,
      trendScore: trendScore,
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
        protectedRevenue: const Money(0),
        totalContractedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        penaltyRecoveryRate: 0,
        disputeToResolutionRatio: 0,
        financialProtectionScore: 0,
        complianceScore: 0,
        evidenceScore: 0,
        recoveryScore: 0,
        trendScore: 50,
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
    final s = 1.0 / (1.0 + _exp(-delta * 0.2));
    return (s * 100).clamp(0.0, 100.0);
  }

  static double _exp(double x) {
    // Dart's math.exp equivalent using series approximation is not needed;
    // use the built-in via import dart:math — but domain must be pure Dart (INV-4).
    // dart:math is a Dart SDK library — no Flutter/Supabase dependency.
    return _dartExp(x);
  }

  // ignore: non_constant_identifier_names
  static double _dartExp(double x) {
    // Use the identity: e^x via Taylor series (sufficient for small deltas)
    // For delta in [-20, 20], the sigmoid is effectively 0 or 1 anyway.
    // We rely on the core Dart math: dart:math is permitted (INV-4 = no FLUTTER).
    // Using a simple iterative approach to avoid importing dart:math:
    if (x > 20) return double.maxFinite / 2; // sigmoid → 1
    if (x < -20) return 0.0000001; // sigmoid → 0
    double result = 1.0;
    double term = 1.0;
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
