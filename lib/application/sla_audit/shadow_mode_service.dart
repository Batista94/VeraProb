import '../../domain/sla_audit/canonical_fact_repository.dart';
import '../../domain/sla_audit/ingestion_integrity_flag.dart';
import '../../domain/sla_audit/shadow_mode_repository.dart';
import '../../domain/sla_audit/shadow_mode_simulation.dart';
import '../../domain/shared/money.dart';
import 'reporting_service.dart';

/// Orchestrates [ShadowModeSimulation] computation and persistence.
///
/// Shadow Mode answers: "What financial losses would have occurred without
/// veraprob's automated SLA enforcement?" — the key ROI proof for sales.
///
/// **Evidence quality attribution (PO directive 2026-03-17):**
/// When [evidenceQualityRate] is low, [ShadowModeSimulation.evidenceQualityAttribution]
/// explicitly attributes this to contractor hardware quality.
/// This service computes [evidenceQualityRate] from the actual canonical_facts
/// integrity flags — it is an objective measurement, not an estimate.
class ShadowModeService {
  final ShadowModeRepository _simulationRepo;
  final ReportingService _reportingService;
  final CanonicalFactRepository _canonicalFactRepo;

  ShadowModeService({
    required ShadowModeRepository simulationRepo,
    required ReportingService reportingService,
    required CanonicalFactRepository canonicalFactRepo,
  }) : _simulationRepo = simulationRepo,
       _reportingService = reportingService,
       _canonicalFactRepo = canonicalFactRepo;

  /// Computes and persists a Shadow Mode ROI simulation for the given period.
  ///
  /// [baselineDisputeRate]: percentage (0–100) of no-show penalties that would
  ///   have been successfully disputed by the contractor without automated evidence.
  ///   A reasonable estimate for fretamento contracts is 40–70%.
  ///
  /// [manualEnforcementCostPerIncident]: estimated labor cost in cents to manually
  ///   track and enforce a single SLA incident.
  ///
  /// [platformSubscriptionCost]: total cost of veraprob for the period (cents).
  ///   Used to compute the ROI percentage.
  Future<ShadowModeSimulation> runSimulation({
    required String organizationId,
    required String simulationName,
    required DateTime periodStartUtc,
    required DateTime periodEndUtc,
    required int baselineDisputeRateBps,
    required Money manualEnforcementCostPerIncident,
    required Money platformSubscriptionCost,
    required String generatedByUserId,
  }) async {
    // 1. Fetch the BillingCycleReport for actual financial data
    final report = await _reportingService.generateBillingCycleReport(
      organizationId: organizationId,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
    );

    // 2. Compute evidence quality rate from canonical_facts integrity flags
    //    This is objective measurement — not an estimate.
    final flagCounts = await _canonicalFactRepo.countByIntegrityFlag(
      organizationId: organizationId,
      fromUtc: periodStartUtc,
      toUtc: periodEndUtc,
    );
    final totalFacts = flagCounts.values.fold(0, (a, b) => a + b);
    final okFacts = flagCounts[IngestionIntegrityFlag.ok] ?? 0;
    final evidenceQualityRateBps = totalFacts > 0
        ? (okFacts * 10000 ~/ totalFacts)
        : 10000;

    // 3. Compute simulation
    final incidentCount = report.noShowCount + report.evidenceGapCount;
    final simulation = ShadowModeSimulation.compute(
      organizationId: organizationId,
      simulationName: simulationName,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      actualProtectedRevenue: report.protectedRevenue,
      actualLostRevenue: report.lostRevenue,
      actualAtRiskRevenue: report.revenueAtRisk,
      actualComplianceRateBps: report.complianceRateBps,
      evidenceQualityRateBps: evidenceQualityRateBps,
      baselineDisputeRateBps: baselineDisputeRateBps,
      manualEnforcementCostPerIncident: manualEnforcementCostPerIncident,
      incidentCount: incidentCount,
      platformSubscriptionCost: platformSubscriptionCost,
      generatedAtUtc: DateTime.now().toUtc(),
      generatedByUserId: generatedByUserId,
      simulationParameters: {
        'baseline_dispute_rate_bps': baselineDisputeRateBps,
        'manual_cost_per_incident_cents':
            manualEnforcementCostPerIncident.cents,
        'platform_subscription_cost_cents': platformSubscriptionCost.cents,
        'evidence_quality_rate_bps': evidenceQualityRateBps,
        'total_canonical_facts': totalFacts,
        'ok_canonical_facts': okFacts,
      },
    );

    await _simulationRepo.save(simulation);
    return simulation;
  }

  /// Returns past simulations for the organization, most recent first.
  Future<List<ShadowModeSimulation>> listSimulations({
    required String organizationId,
    int limit = 10,
  }) => _simulationRepo.findByOrganization(
    organizationId: organizationId,
    limit: limit,
  );
}
