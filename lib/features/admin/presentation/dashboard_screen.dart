import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'widgets/contractual_risk_radar.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/projections/providers/feed_health_projection_provider.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/presentation/shell/widgets/onboarding_progress_banner.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/dashboard_risk_feed_provider.dart';
import 'package:veraprob/state/providers/sla_financial_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

/// Tier-1 OCC dashboard: an asymmetric Bento grid prioritising actionable
/// financial signal over decoration. Left pane = financial KPIs (1-tap
/// drill-down) + telemetry confidence; right pane = the severity-sorted
/// command feed.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;

        const leftPane = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FinancialKpiRow(),
            SizedBox(height: 24),
            _TelemetryConfidenceCard(),
          ],
        );

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              child: ref.watch(onboardingBannerVisibleProvider)
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: OnboardingProgressBanner(
                        onNavigate: (destIdx) {
                          context.go(AdminNav.values[destIdx].path);
                          ref
                              .read(selectedContractIdProvider.notifier)
                              .set(null);
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const _DashboardHeader(),
            const SizedBox(height: 32),
            if (isWide)
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: leftPane),
                  SizedBox(width: 24),
                  Expanded(flex: 1, child: RiskFeedList()),
                ],
              )
            else ...[
              leftPane,
              const SizedBox(height: 24),
              const RiskFeedList(),
            ],
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: VeraProbColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: VeraProbColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.analytics_rounded,
                size: 32,
                color: VeraProbColors.primary,
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Painel de Controle',
                  style: VeraProbTypography.kpiValue.copyWith(
                    fontSize: 32,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: VeraProbColors.onTime,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Operação em Tempo Real • Receita Protegida',
                      style: VeraProbTypography.bodySmall.copyWith(
                        color: VeraProbColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        if (kDebugMode) const _DevSeedButton(),
      ],
    );
  }
}

/// Telemetry confidence promoted from the app-bar badge to a full KPI cell.
class _TelemetryConfidenceCard extends ConsumerWidget {
  const _TelemetryConfidenceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(feedHealthProjectionProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: health.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors_rounded, size: 16, color: health.color),
              const SizedBox(width: 8),
              Text(
                'SAÚDE DA INGESTÃO DE TELEMETRIA',
                style: VeraProbTypography.kpiLabel,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: health.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                health.label.toUpperCase(),
                style: VeraProbTypography.kpiValue.copyWith(
                  color: health.color,
                  fontSize: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Debug-only operation simulator. Lives in its own widget so production
/// builds never reserve layout for it.
class _DevSeedButton extends ConsumerWidget {
  const _DevSeedButton();

  Future<void> _seedData(BuildContext context, WidgetRef ref) async {
    final organizationId = ref.read(currentOrganizationIdProvider);
    if (organizationId == null) return;
    try {
      final repository = ref.read(dataSeedingRepositoryProvider);
      await repository.seedCsvData(organizationId);
      await repository.seedDrivers(organizationId);
      await repository.seedRoutes(organizationId);
      await repository.seedHistoricalData(organizationId);
      await repository.seedActiveSanctions(organizationId);
      await runSanctionSimulation(
        ref,
        organizationId: organizationId,
        vehiclePlate: 'VPR-0001',
      );
      await repository.seedPhase9(organizationId);
      await ref
          .read(simulationSeedServiceProvider)
          .seedFinancialSnapshots(organizationId);

      // Invalidate cached providers so the onboarding checklist updates
      ref.invalidate(contractorListProvider);
      ref.invalidate(operationalZonesProvider);
      ref.invalidate(contractListProvider);
      ref.invalidate(slaTemplatesProvider);
      ref.invalidate(financialImpactProvider);
      ref.invalidate(financialSparklineProvider);
      ref.invalidate(dashboardRiskFeedProvider);
      ref.invalidate(activeAlertsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados de teste inseridos.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao inserir dados: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      onPressed: () => _seedData(context, ref),
      icon: const Icon(Icons.bolt_rounded, size: 18),
      label: const Text('SIMULAR OPERAÇÃO'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }
}
