import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sla_audit/projections/executive_dashboard_view.dart';
import '../../application/sla_audit/reporting_service.dart';
import '../../application/sla_audit/shadow_mode_service.dart';
import '../../domain/sla_audit/canonical_fact_repository.dart';
import '../../domain/sla_audit/shadow_mode_simulation.dart';
import '../../infrastructure/sla_audit/in_memory_canonical_fact_repository.dart';
import '../../infrastructure/sla_audit/in_memory_shadow_mode_repository.dart';
import '../providers/auth_providers.dart';
import 'audit_package_providers.dart';
import 'sla_financial_providers.dart';

// ── Canonical Fact Repository ────────────────────────────────────────────────

final canonicalFactRepositoryProvider = Provider<CanonicalFactRepository>((
  ref,
) {
  // Phase 7.2: swap to PostgresCanonicalFactRepository for Postgres mode
  return InMemoryCanonicalFactRepository();
});

// ── Shadow Mode Repository & Service ────────────────────────────────────────

final _shadowModeRepositoryProvider = Provider((ref) {
  // Phase 7.2: swap to PostgresShadowModeRepository for Postgres mode
  return InMemoryShadowModeRepository();
});

final shadowModeServiceProvider = Provider<ShadowModeService>((ref) {
  final shadowRepo = ref.watch(_shadowModeRepositoryProvider);
  final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
  final canonicalFactRepo = ref.watch(canonicalFactRepositoryProvider);
  return ShadowModeService(
    simulationRepo: shadowRepo,
    reportingService: ReportingService(snapshotRepo: snapshotRepo),
    canonicalFactRepo: canonicalFactRepo,
  );
});

// ── Shadow Mode Simulations ──────────────────────────────────────────────────

final shadowModeSimulationsProvider =
    FutureProvider<List<ShadowModeSimulation>>((ref) async {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return const [];

      final service = ref.watch(shadowModeServiceProvider);
      return service.listSimulations(organizationId: organizationId, limit: 5);
    });

// ── Executive Dashboard View ────────────────────────────────────────────────

/// Computes the [ExecutiveDashboardView] for the current period.
///
/// Uses the most recent 12 months of sealed packages for trend data.
/// Returns [ExecutiveDashboardView.empty] when no data is available.
final executiveDashboardProvider = FutureProvider<ExecutiveDashboardView>((
  ref,
) async {
  final organizationId = ref.watch(currentOrganizationIdProvider);
  if (organizationId == null) {
    return ExecutiveDashboardView.empty('');
  }

  final now = DateTime.now().toUtc();
  final periodStart = DateTime.utc(now.year, now.month, 1);
  final periodEnd = now;

  final snapshotRepo = ref.watch(financialSnapshotRepositoryProvider);
  final reportingService = ReportingService(snapshotRepo: snapshotRepo);

  final report = await reportingService.generateBillingCycleReport(
    organizationId: organizationId,
    periodStartUtc: periodStart,
    periodEndUtc: periodEnd,
  );

  final sealedPackages = await ref.watch(sealedAuditPackagesProvider.future);
  final recentIds = sealedPackages.take(3).map((p) => p.id).toList();

  final latestShadowMode = await ref
      .watch(shadowModeSimulationsProvider.future)
      .then((list) => list.isNotEmpty ? list.first : null);

  return ExecutiveDashboardView.compute(
    organizationId: organizationId,
    periodStartUtc: periodStart,
    periodEndUtc: periodEnd,
    protectedRevenue: report.protectedRevenue,
    totalContractedRevenue: report.totalContractedRevenue,
    revenueAtRisk: report.revenueAtRisk,
    lostRevenue: report.lostRevenue,
    totalObligations: report.totalObligations,
    executedCount: report.executedCount,
    noShowCount: report.noShowCount,
    evidenceGapCount: report.evidenceGapCount,
    okCanonicalFacts: 0,
    totalCanonicalFacts: 0,
    compensatingEntryCount: 0,
    complianceTrend: const [],
    recentSealedPackageIds: recentIds,
    latestShadowMode: latestShadowMode,
  );
});

/// FPS sub-score extracted for widgets that only need the gauge value.
final financialProtectionScoreProvider = Provider<double>((ref) {
  final dashboard = ref.watch(executiveDashboardProvider).valueOrNull;
  return dashboard?.financialProtectionScore ?? 0.0;
});
