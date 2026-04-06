import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'domain_exception.dart';

/// Read model for a Shadow Mode ROI simulation.
///
/// Answers the question: "What financial losses would have occurred without
/// veraprob's automated SLA enforcement?"
///
/// This is a comparison model — it holds both the actual platform information
/// and a simulated "without-platform" baseline scenario, producing an
/// [roiPercentage] that quantifies the platform's financial protection value.
///
/// **How to present EvidenceScore to clients (PO directive 2026-03-17):**
/// When [evidenceQualityRate] is low, the [evidenceQualityAttribution] text
/// explicitly attributes this to hardware quality (the contratante's GPS devices),
/// NOT to veraprob's software. This protects the operator's legal position.
///
/// **INV-2:** All monetary values stored as [Money] (cents). Never IEEE-754 values.
/// **INV-3:** All timestamps UTC.
/// **INV-4:** Zero Flutter/Supabase dependencies.
class ShadowModeSimulation extends Equatable {
  // ── Identity ──────────────────────────────────────────────────────────────
  final String id;
  final String organizationId;
  final String simulationName;

  // ── Period ─────────────────────────────────────────────────────────────────
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;

  // ── Actual platform information ───────────────────────────────────────────────────
  final Money actualProtectedRevenue;
  final Money actualLostRevenue;
  final Money actualAtRiskRevenue;

  /// Compliance rate achieved WITH veraprob (executedCount / totalObligations × 100).
  final int actualComplianceRateBps;

  /// Ratio of canonical_facts with integrity_flag = OK over total facts (0.0–100.0).
  /// Low values indicate poor hardware quality at the contractor's fleet.
  final int evidenceQualityRateBps;

  // ── Simulated baseline (without-platform scenario) ─────────────────────────
  /// Estimated percentage of no-show penalties that would have been successfully
  /// disputed without automated evidence (e.g., 60%).
  final int baselineDisputeRateBps;

  /// Estimated labor cost per incident for manual SLA tracking (in cents).
  final Money manualEnforcementCostPerIncident;

  /// Total number of SLA incidents in the period.
  final int incidentCount;

  // ── Computed ROI ───────────────────────────────────────────────────────────
  /// Revenue that would have been lost without platform enforcement.
  final Money simulatedLostRevenue;

  /// Revenue protected by the platform = actual_lost − simulated_lost
  ///   + (manual_cost × incident_count).
  final Money revenueProtectedByPlatform;

  /// (revenueProtectedByPlatform / platformSubscriptionCost) × 100.
  final int roiPercentageBps;

  // ── Meta ───────────────────────────────────────────────────────────────────
  final Map<String, dynamic> simulationParameters;
  final DateTime generatedAtUtc;
  final String generatedByUserId;

  const ShadowModeSimulation._({
    required this.id,
    required this.organizationId,
    required this.simulationName,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.actualProtectedRevenue,
    required this.actualLostRevenue,
    required this.actualAtRiskRevenue,
    required this.actualComplianceRateBps,
    required this.evidenceQualityRateBps,
    required this.baselineDisputeRateBps,
    required this.manualEnforcementCostPerIncident,
    required this.incidentCount,
    required this.simulatedLostRevenue,
    required this.revenueProtectedByPlatform,
    required this.roiPercentageBps,
    required this.simulationParameters,
    required this.generatedAtUtc,
    required this.generatedByUserId,
  });

  factory ShadowModeSimulation.compute({
    required String organizationId,
    required String simulationName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required Money actualProtectedRevenue,
    required Money actualLostRevenue,
    required Money actualAtRiskRevenue,
    required int actualComplianceRateBps,
    required int evidenceQualityRateBps,
    required int baselineDisputeRateBps,
    required Money manualEnforcementCostPerIncident,
    required int incidentCount,
    required Money platformSubscriptionCost,
    required DateTime generatedAtUtc,
    required String generatedByUserId,
    Map<String, dynamic> simulationParameters = const {},
  }) {
    if (organizationId.trim().isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    if (!periodStartUtc.isUtc || !periodEndUtc.isUtc || !generatedAtUtc.isUtc) {
      throw const DomainException('All DateTime fields must be UTC (INV-3).');
    }
    if (baselineDisputeRateBps < 0 || baselineDisputeRateBps > 10000) {
      throw const DomainException(
        'baselineDisputeRateBps must be between 0 and 10000.',
      );
    }
    if (evidenceQualityRateBps < 0 || evidenceQualityRateBps > 10000) {
      throw const DomainException(
        'evidenceQualityRateBps must be between 0 and 10000.',
      );
    }

    // Simulation: revenue that would have leaked without enforcement
    final simulatedLost = Money(
      (actualLostRevenue.cents * (10000 - baselineDisputeRateBps) ~/ 10000),
    );

    // Manual enforcement labor cost savings
    final manualCostTotal =
        manualEnforcementCostPerIncident * incidentCount.toDouble();

    // Revenue protected = (penalties that would have been waived) + labor savings
    final protected = Money(
      actualLostRevenue.cents - simulatedLost.cents + manualCostTotal.cents,
    );

    final int roiBps = platformSubscriptionCost.cents > 0
        ? (protected.cents * 10000 ~/ platformSubscriptionCost.cents)
        : 0;

    return ShadowModeSimulation._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      simulationName: simulationName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      actualProtectedRevenue: actualProtectedRevenue,
      actualLostRevenue: actualLostRevenue,
      actualAtRiskRevenue: actualAtRiskRevenue,
      actualComplianceRateBps: actualComplianceRateBps,
      evidenceQualityRateBps: evidenceQualityRateBps,
      baselineDisputeRateBps: baselineDisputeRateBps,
      manualEnforcementCostPerIncident: manualEnforcementCostPerIncident,
      incidentCount: incidentCount,
      simulatedLostRevenue: simulatedLost,
      revenueProtectedByPlatform: protected,
      roiPercentageBps: roiBps,
      simulationParameters: Map.unmodifiable(simulationParameters),
      generatedAtUtc: generatedAtUtc,
      generatedByUserId: generatedByUserId,
    );
  }

  factory ShadowModeSimulation.reconstitute({
    required String id,
    required String organizationId,
    required String simulationName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required Money actualProtectedRevenue,
    required Money actualLostRevenue,
    required Money actualAtRiskRevenue,
    required int actualComplianceRateBps,
    required int evidenceQualityRateBps,
    required int baselineDisputeRateBps,
    required Money manualEnforcementCostPerIncident,
    required int incidentCount,
    required Money simulatedLostRevenue,
    required Money revenueProtectedByPlatform,
    required int roiPercentageBps,
    required Map<String, dynamic> simulationParameters,
    required DateTime generatedAtUtc,
    required String generatedByUserId,
  }) {
    return ShadowModeSimulation._(
      id: id,
      organizationId: organizationId,
      simulationName: simulationName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      actualProtectedRevenue: actualProtectedRevenue,
      actualLostRevenue: actualLostRevenue,
      actualAtRiskRevenue: actualAtRiskRevenue,
      actualComplianceRateBps: actualComplianceRateBps,
      evidenceQualityRateBps: evidenceQualityRateBps,
      baselineDisputeRateBps: baselineDisputeRateBps,
      manualEnforcementCostPerIncident: manualEnforcementCostPerIncident,
      incidentCount: incidentCount,
      simulatedLostRevenue: simulatedLostRevenue,
      revenueProtectedByPlatform: revenueProtectedByPlatform,
      roiPercentageBps: roiPercentageBps,
      simulationParameters: simulationParameters,
      generatedAtUtc: generatedAtUtc,
      generatedByUserId: generatedByUserId,
    );
  }

  /// Human-readable attribution text for low evidence quality.
  ///
  /// When [evidenceQualityRate] < 80%, this text attributes the quality gap
  /// to the contratante's GPS hardware, not to veraprob software.
  /// Operators should include this text in reports to protect their legal position.
  String get evidenceQualityAttribution {
    if (evidenceQualityRateBps >= 9500) {
      return 'Qualidade de telemetria excelente (${(evidenceQualityRateBps / 100).toStringAsFixed(1)}%). '
          'Hardware do contratante está operando dentro dos parâmetros esperados.';
    }
    if (evidenceQualityRateBps >= 8000) {
      return 'Qualidade de telemetria adequada (${(evidenceQualityRateBps / 100).toStringAsFixed(1)}%). '
          'Eventuais lacunas de evidência são atribuíveis à latência de rede ou '
          'precisão do hardware GPS do contratante.';
    }
    return 'ATENÇÃO — Qualidade de telemetria abaixo do esperado '
        '(${(evidenceQualityRateBps / 100).toStringAsFixed(1)}%). '
        'A redução na pontuação de evidência é atribuída à qualidade do hardware GPS '
        'instalado na frota do contratante (classificações: KINEMATIC_ANOMALY, '
        'NULL_ISLAND, LOW_ACCURACY, FUTURE_TIMESTAMP). '
        'O operador recomenda que o contratante audite e atualize os dispositivos '
        'de rastreamento para garantir precisão máxima na proteção contratual. '
        'veraprob processou 100% dos sinais válidos recebidos.';
  }

  @override
  List<Object?> get props => [id];
}
